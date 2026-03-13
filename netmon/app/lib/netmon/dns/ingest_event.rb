# frozen_string_literal: true

require "digest"
require "ipaddr"
require "json"

module Netmon
  module Dns
    class IngestEvent
      ANSWER_TYPES = %w[A AAAA].freeze

      def self.call(router_id:, data:, ts:)
        payload = normalize_hash(data)
        unless valid_payload?(payload)
          Rails.logger.warn("[dns_ingest] invalid dns_response payload router_id=#{router_id}")
          return nil
        end

        answers = normalize_answers(payload["answers"])
        if answers.nil?
          Rails.logger.warn("[dns_ingest] invalid answers payload router_id=#{router_id}")
          return nil
        end

        observed_at = ts || Time.current
        dedupe_key = build_dedupe_key(router_id:, observed_at:, payload:, answers:)

        begin
          existing = DnsEvent.find_by(dedupe_key: dedupe_key)
          return existing if existing

          dns_event = DnsEvent.create!(
            router_id: router_id.to_s,
            observed_at: observed_at,
            client_ip: payload["client_ip"].to_s,
            qname: payload["qname"].to_s,
            qtype: payload["qtype"].to_s.upcase,
            rcode: payload["rcode"].presence,
            resolver: payload["resolver"].presence,
            answers_json: JSON.generate(payload["answers"] || []),
            dedupe_key: dedupe_key
          )

          answers.each do |answer|
            DnsEventAnswer.create!(
              dns_event: dns_event,
              answer_ip: answer["answer_ip"],
              answer_type: answer["answer_type"]
            )
          end

          dns_event
        rescue ActiveRecord::RecordNotUnique
          DnsEvent.find_by(dedupe_key: dedupe_key)
        rescue StandardError => e
          Rails.logger.error(
            "[dns_ingest] failed router_id=#{router_id} error=#{e.class}: #{e.message}"
          )
          nil
        end
      end

      def self.valid_payload?(payload)
        required = %w[client_ip qname qtype]
        required.all? { |k| payload[k].present? }
      end
      private_class_method :valid_payload?

      def self.normalize_hash(data)
        return {} if data.nil?

        if data.respond_to?(:to_unsafe_h)
          data = data.to_unsafe_h
        elsif data.respond_to?(:to_h)
          data = data.to_h
        end
        return {} unless data.is_a?(Hash)

        data.transform_keys(&:to_s)
      rescue StandardError
        {}
      end
      private_class_method :normalize_hash

      def self.normalize_answers(raw_answers)
        return [] if raw_answers.nil?
        return nil unless raw_answers.is_a?(Array)

        raw_answers.filter_map do |raw_answer|
          next unless raw_answer.is_a?(Hash)

          answer = raw_answer.transform_keys(&:to_s)
          answer_type = answer["type"].to_s.upcase
          answer_ip = answer["data"].to_s
          next unless ANSWER_TYPES.include?(answer_type)
          next unless valid_ip?(answer_ip)

          {
            "answer_type" => answer_type,
            "answer_ip" => answer_ip
          }
        end
      end
      private_class_method :normalize_answers

      def self.valid_ip?(value)
        IPAddr.new(value)
        true
      rescue IPAddr::InvalidAddressError
        false
      end
      private_class_method :valid_ip?

      def self.build_dedupe_key(router_id:, observed_at:, payload:, answers:)
        normalized_payload = {
          "router_id" => router_id.to_s,
          "observed_at" => observed_at.utc.iso8601(6),
          "client_ip" => payload["client_ip"].to_s,
          "qname" => payload["qname"].to_s.downcase,
          "qtype" => payload["qtype"].to_s.upcase,
          "rcode" => payload["rcode"].to_s.upcase,
          "resolver" => payload["resolver"].to_s,
          "answers" => answers.sort_by { |a| [a["answer_type"], a["answer_ip"]] }
        }

        Digest::SHA256.hexdigest(JSON.generate(normalized_payload))
      end
      private_class_method :build_dedupe_key
    end
  end
end
