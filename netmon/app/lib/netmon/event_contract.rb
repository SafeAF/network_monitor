# frozen_string_literal: true

require "ipaddr"
require "date"
require "json"
require "openssl"
require "time"

module Netmon
  class EventContract
    MAX_EVENTS = 500
    MAX_EVENT_BYTES = 32 * 1024
    MAX_REPLAY_AGE = 30 * 24 * 60 * 60
    FUTURE_SKEW = 300
    TYPES = %w[flow dns_response firewall_drop heartbeat].freeze
    MAX_COUNTER = (2**63) - 1

    class Invalid < StandardError; end

    def self.batch!(payload)
      fail_with("invalid_batch") unless payload.is_a?(Hash)
      router = payload["router_id"]
      fail_with("invalid_router_id") unless router.is_a?(String) && router.match?(/\A[A-Za-z0-9][A-Za-z0-9_.:-]{0,63}\z/)
      events = payload["events"]
      fail_with("invalid_events") unless events.is_a?(Array) && events.length <= MAX_EVENTS
      [router, events]
    end

    def self.event!(raw, sent_at: nil, now: Time.now)
      fail_with("invalid_event") unless raw.is_a?(Hash)
      fail_with("event_too_large") if JSON.generate(raw).bytesize > MAX_EVENT_BYTES
      type = raw["type"]
      fail_with("unsupported_type") unless TYPES.include?(type)
      data = raw["data"]
      fail_with("invalid_data") unless data.is_a?(Hash) && bounded_tree?(data)
      ts = timestamp!(raw.key?("ts") ? raw["ts"] : sent_at)
      fail_with("timestamp_out_of_range") if ts < now - MAX_REPLAY_AGE || ts > now + FUTURE_SKEW

      case type
      when "flow", "firewall_drop"
        if data.key?("flow_id")
          fail_with("invalid_flow_id") unless data["flow_id"].is_a?(String) && data["flow_id"].match?(/\A[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}\z/)
        end
        %w[src_ip dst_ip].each { |key| fail_with("invalid_ip") unless ip?(data[key]) }
        %w[src_port dst_port].each { |key| integer!(data[key], 65_535) unless data[key].nil? }
        proto = data["l4proto"]
        integer!(proto, 255) unless %w[tcp udp icmp icmpv6].include?(proto)
        %w[event state flags dir hook rule_tag if_in if_out].each { |key| optional_text!(data, key, 512) }
        integer!(data["nflog_group"], 65_535) unless data["nflog_group"].nil?
        fail_with("invalid_boolean") if data.key?("tcp_syn") && ![true, false].include?(data["tcp_syn"])
        %w[bytes_orig bytes_reply packets_orig packets_reply].each do |key|
          integer!(data[key], MAX_COUNTER) unless data[key].nil?
        end
        %w[first_seen last_seen].each do |key|
          next if data[key].nil?
          time = timestamp!(data[key])
          fail_with("timestamp_out_of_range") if time.year < 2000 || time > now + FUTURE_SKEW
        end
      when "dns_response"
        fail_with("invalid_client_ip") unless ip?(data["client_ip"])
        fail_with("invalid_qname") unless text?(data["qname"], 253)
        fail_with("invalid_qtype") unless data["qtype"].is_a?(String) && data["qtype"].match?(/\A[A-Za-z0-9]{1,16}\z/)
        %w[rcode resolver].each { |key| optional_text!(data, key, 255) }
        answers = data.fetch("answers", [])
        fail_with("invalid_answers") unless answers.is_a?(Array) && answers.length <= 64
        answers.each do |answer|
          fail_with("invalid_answer") unless answer.is_a?(Hash) && text?(answer["type"], 16) && text?(answer["data"], 1024)
          if %w[A AAAA].include?(answer["type"].upcase)
            fail_with("invalid_answer_ip") unless ip?(answer["data"])
            ipv4 = IPAddr.new(answer["data"]).ipv4?
            fail_with("invalid_answer_family") unless ipv4 == (answer["type"].upcase == "A")
          end
        end
      end

      fingerprint = OpenSSL::Digest.hexdigest("SHA256", JSON.generate(canonical([type, ts.utc.iso8601(9), data])))
      id = raw.key?("id") ? raw["id"] : "legacy-#{fingerprint}"
      fail_with("invalid_id") unless id.is_a?(String) && id.match?(/\A[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}\z/)
      { event_uid: id, payload_digest: fingerprint, event_type: type, ts: ts, data: data }
    rescue JSON::GeneratorError, EncodingError
      fail_with("invalid_encoding")
    end

    def self.timestamp!(value)
      fail_with("invalid_timestamp") unless value.is_a?(String) && value.bytesize <= 40 &&
        value.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})\z/)
      year, month, day = value[0, 10].split("-").map(&:to_i)
      fail_with("invalid_timestamp") unless Date.valid_date?(year, month, day)
      Time.iso8601(value)
    rescue ArgumentError
      fail_with("invalid_timestamp")
    end

    def self.ip?(value)
      return false unless value.is_a?(String) && value.bytesize <= 45 && value.match?(/\A[0-9a-fA-F:.]+\z/)
      IPAddr.new(value)
      true
    rescue IPAddr::InvalidAddressError
      false
    end

    def self.integer!(value, maximum)
      valid = value.is_a?(Integer) || (value.is_a?(String) && value.match?(/\A\d{1,19}\z/))
      fail_with("invalid_integer") unless valid && value.to_i.between?(0, maximum)
    end

    def self.text?(value, maximum)
      value.is_a?(String) && !value.empty? && value.valid_encoding? && value.bytesize <= maximum && !value.match?(/[\x00-\x1f\x7f]/)
    end

    def self.optional_text!(data, key, maximum)
      value = data[key]
      fail_with("invalid_field_type") unless value.nil? || value == "" || text?(value, maximum)
    end

    def self.bounded_tree?(value, depth = 0)
      return false if depth > 6
      case value
      when Hash
        value.length <= 64 && value.all? { |key, child| text?(key, 64) && bounded_tree?(child, depth + 1) }
      when Array
        value.length <= 256 && value.all? { |child| bounded_tree?(child, depth + 1) }
      when String
        value.valid_encoding? && value.bytesize <= 1024 && !value.match?(/[\x00-\x1f\x7f]/)
      when Integer then value.between?(-MAX_COUNTER, MAX_COUNTER)
      when TrueClass, FalseClass, NilClass then true
      else false
      end
    end

    def self.canonical(value)
      case value
      when Hash then value.sort.to_h.transform_values { |child| canonical(child) }
      when Array then value.map { |child| canonical(child) }
      else value
      end
    end

    def self.fail_with(code)
      raise Invalid, code
    end
    private_class_method :timestamp!, :integer!, :text?, :optional_text!, :bounded_tree?, :canonical, :fail_with
  end
end
