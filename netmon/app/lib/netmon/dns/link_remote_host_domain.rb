# frozen_string_literal: true

module Netmon
  module Dns
    class LinkRemoteHostDomain
      def self.call(remote_host:, domain:, device_ip:, seen_at:)
        return if remote_host.nil? || domain.blank?

        seen_time = seen_at || Time.current
        record = RemoteHostDomain.find_or_initialize_by(
          remote_host_id: remote_host.id,
          domain: domain
        )
        record.first_seen_at ||= seen_time
        record.last_seen_at = seen_time
        record.last_device_ip = device_ip if device_ip.present?
        record.seen_count = record.seen_count.to_i + 1
        record.save!
      rescue StandardError => e
        Rails.logger.error(
          "[dns_link] failed remote_host_id=#{remote_host&.id} domain=#{domain} error=#{e.class}: #{e.message}"
        )
      end
    end
  end
end
