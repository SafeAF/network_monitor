# frozen_string_literal: true

module Netmon
  module Dns
    class CorrelateConnection
      DEFAULT_WINDOW = 10.minutes

      def self.call(connection:, router_id:, now: Time.current, window: DEFAULT_WINDOW)
        return nil if connection.src_ip.blank? || connection.dst_ip.blank?
        RouterScope.authorize!(router_id)

        answer = direct_answer_for(connection: connection, router_id: router_id, now: now, window: window)

        return nil unless answer

        {
          domain: answer.qname,
          observed_at: normalize_time(answer.observed_at)
        }
      end

      def self.normalize_time(value)
        return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)

        Time.zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
      private_class_method :normalize_time

      def self.direct_answer_for(connection:, router_id:, now:, window:)
        DnsEventAnswer
          .joins(:dns_event)
          .where(answer_ip: connection.dst_ip)
          .where(dns_events: { router_id: router_id, client_ip: connection.src_ip, qtype: %w[A AAAA], rcode: [nil, "", "NOERROR"] })
          .where("dns_events.observed_at >= ? AND dns_events.observed_at <= ?", now - window, now)
          .order("dns_events.observed_at DESC")
          .select("dns_event_answers.id, dns_events.qname, dns_events.observed_at")
          .first
      end
      private_class_method :direct_answer_for
    end
  end
end
