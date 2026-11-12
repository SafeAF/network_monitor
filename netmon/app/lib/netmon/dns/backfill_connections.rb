# frozen_string_literal: true

module Netmon
  module Dns
    class BackfillConnections
      DEFAULT_WINDOW = 10.minutes

      def self.call(dns_event:, window: DEFAULT_WINDOW, strict: false)
        RouterScope.authorize!(dns_event.router_id)
        return 0 unless %w[A AAAA].include?(dns_event.qtype.to_s.upcase)
        return 0 unless ["", "NOERROR"].include?(dns_event.rcode.to_s.upcase)
        answer_ips = dns_event.dns_event_answers.pluck(:answer_ip).uniq
        return 0 if answer_ips.empty?

        scope = scope_for(dns_event:, answer_ips:, window:)

        updated = 0
        scope.find_each do |connection|
          next if connection.last_domain_observed_at.present? && connection.last_domain_observed_at >= dns_event.observed_at

          connection.last_domain = dns_event.qname
          connection.last_domain_observed_at = dns_event.observed_at
          connection.save!
          updated += 1

          remote_host = RemoteHost.find_by(ip: connection.dst_ip)
          next unless remote_host

          Netmon::Dns::LinkRemoteHostDomain.call(
            remote_host: remote_host,
            domain: dns_event.qname,
            device_ip: connection.src_ip,
            seen_at: dns_event.observed_at,
            strict: strict
          )
        end

        updated
      rescue StandardError => e
        raise if strict
        Rails.logger.error(
          "[dns_backfill] failed dns_event_id=#{dns_event&.id} error=#{e.class}: #{e.message}"
        )
        0
      end

      def self.scope_for(dns_event:, answer_ips:, window:)
        Connection.where(dst_ip: answer_ips, src_ip: dns_event.client_ip)
                          .where("last_seen_at >= ? AND last_seen_at <= ?",
                                 dns_event.observed_at,
                                 dns_event.observed_at + window)
      end
      private_class_method :scope_for
    end
  end
end
