# frozen_string_literal: true

module Netmon
  module Dns
    class CorrelateConnection
      DEFAULT_WINDOW = 10.minutes

      def self.call(connection:, now: Time.current, window: DEFAULT_WINDOW)
        return nil if connection.src_ip.blank? || connection.dst_ip.blank?

        answer = DnsEventAnswer
                 .joins(:dns_event)
                 .where(answer_ip: connection.dst_ip)
                 .where(dns_events: { client_ip: connection.src_ip })
                 .where("dns_events.observed_at >= ?", now - window)
                 .order("dns_events.observed_at DESC")
                 .select("dns_event_answers.id, dns_events.qname, dns_events.observed_at")
                 .first

        return nil unless answer

        {
          domain: answer.qname,
          observed_at: answer.observed_at
        }
      end
    end
  end
end
