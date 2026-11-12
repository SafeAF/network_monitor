# frozen_string_literal: true

require "openssl"
require "json"

module Netmon
  class FlowLifetimes
    Result = Struct.new(:lifetime, :accounting, keyword_init: true)

    def self.apply!(router_id:, tuple:, data:, now:, connection:)
      tuple_key = OpenSSL::Digest.hexdigest("SHA256", JSON.generate(tuple.sort.to_h))
      explicit = data["flow_id"].present?
      opening = lifecycle(data) == "NEW"
      terminal = lifecycle(data) == "DESTROY"
      if explicit
        row = AgentFlowLifetime.lock.find_or_initialize_by(router_id: router_id, flow_uid: "id:#{data['flow_id']}")
      else
        scope = AgentFlowLifetime.where(router_id: router_id, legacy_key: tuple_key)
        row = scope.where("first_observed_at <= ?", now).order(first_observed_at: :desc, id: :desc).lock.first
        row = nil if row && opening && row.closed_at && now > row.closed_at
        # A late NEW can precede the first observed (terminal) event. Match
        # that provisional lifetime instead of crediting its counters twice.
        row ||= scope.where(opening_seen: false).where("closed_at >= ?", now).order(:first_observed_at, :id).lock.first if opening
        row ||= AgentFlowLifetime.new(router_id: router_id, flow_uid: "legacy:#{tuple_key}:#{now.utc.iso8601(9)}", legacy_key: tuple_key)
      end
      if row.persisted? && row.tuple_key != tuple_key
        raise EventContract::Invalid, "flow_identity_conflict"
      end
      previous = if row.persisted?
        { counters: row.counters, observed_at: row.last_observed_at, closed: row.closed_at.present? }
      elsif !explicit && connection.persisted? && connection.agent_flow_uid.nil? && connection.last_delta_at
        # Preserve the pre-migration counter baseline for the existing legacy
        # projection; historical rollups are not credited a second time.
        row.first_observed_at = connection.first_seen_at
        { counters: { "bytes_orig" => connection.last_uplink_bytes.to_i, "bytes_reply" => connection.last_downlink_bytes.to_i,
          "packets_orig" => connection.last_uplink_packets.to_i, "packets_reply" => connection.last_downlink_packets.to_i },
          observed_at: connection.last_delta_at, closed: false }
      elsif !explicit && connection.last_delta_at && now < connection.last_delta_at
        # Old unidentifiable replay must not manufacture a new lifetime.
        { counters: FlowAccounting::COUNTERS.to_h { |key| [key, 0] }, observed_at: connection.last_delta_at, closed: false }
      end
      accounting = FlowAccounting.advance(previous: previous, counters: data, observed_at: now, terminal: terminal)
      return Result.new(lifetime: row, accounting: accounting) if accounting.stale

      row.tuple_key = tuple_key
      row.first_observed_at ||= now
      row.last_observed_at = now
      row.closed_at ||= now if terminal
      row.opening_seen ||= opening
      accounting.counters.each { |key, value| row.public_send("#{key}=", value) }
      row.save!
      Result.new(lifetime: row, accounting: accounting)
    end

    def self.lifecycle(data)
      (data["event"].presence || data["state"]).to_s.sub(/\AEvent/i, "").upcase
    end
    private_class_method :lifecycle
  end
end
