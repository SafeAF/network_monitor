# frozen_string_literal: true

module Netmon
  class BatchIngest
    def self.call(payload, now: Time.current)
      router_id, events = EventContract.batch!(payload)
      results = events.each_with_index.map do |raw, index|
        process(raw, router_id: router_id, sent_at: payload["sent_at"], now: now).merge(index: index)
      end
      {
        protocol_version: 1,
        accepted: results.count { |result| %w[accepted duplicate].include?(result[:status]) },
        rejected: results.count { |result| result[:status] == "rejected" },
        retryable: results.count { |result| result[:status] == "retryable" },
        results: results
      }
    end

    def self.process(raw, router_id:, sent_at:, now:)
      attributes = EventContract.event!(raw, sent_at: sent_at, now: now).merge(router_id: router_id)
      existing = NetmonEvent.find_by(router_id: router_id, event_uid: attributes[:event_uid])
      return duplicate_result(existing, attributes) if existing

      # Rescue outside this boundary: a failed event must leave neither its raw
      # receipt nor any partial normalized records behind.
      completed = NetmonEvent.transaction(requires_new: true) do
        NetmonEvent.create!(attributes)
        AgentIngest.ingest_event!(event_type: attributes[:event_type], router_id: router_id,
          data: attributes[:data], ts: attributes[:ts])
        true
      end
      completed ? { status: "accepted" } : { status: "retryable", code: "processing_failed" }
    rescue EventContract::Invalid => e
      { status: "rejected", code: e.message }
    rescue ActiveRecord::RecordNotUnique
      existing = NetmonEvent.find_by(router_id: router_id, event_uid: attributes[:event_uid])
      existing ? duplicate_result(existing, attributes) : { status: "retryable", code: "processing_failed" }
    rescue StandardError => e
      Rails.logger.error("[agent_ingest] event failed router_id=#{router_id} error=#{e.class}")
      { status: "retryable", code: "processing_failed" }
    end
    private_class_method :process

    def self.duplicate_result(existing, attributes)
      existing.payload_digest == attributes[:payload_digest] ? { status: "duplicate" } : { status: "rejected", code: "id_conflict" }
    end
    private_class_method :duplicate_result
  end
end
