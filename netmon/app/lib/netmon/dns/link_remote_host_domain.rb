# frozen_string_literal: true

module Netmon
  module Dns
    class LinkRemoteHostDomain
      def self.call(remote_host:, domain:, device_ip:, seen_at:, strict: false)
        return if remote_host.nil? || domain.blank?

        seen_time = seen_at || Time.current
        record = RemoteHostDomain.find_or_initialize_by(
          remote_host_id: remote_host.id,
          domain: domain
        )
        newest_observation = record.last_seen_at.nil? || seen_time >= record.last_seen_at
        record.first_seen_at = [record.first_seen_at, seen_time].compact.min
        record.last_seen_at = [record.last_seen_at, seen_time].compact.max
        record.last_device_ip = device_ip if device_ip.present? && newest_observation
        record.seen_count = record.seen_count.to_i + 1
        record.save!
      rescue StandardError => e
        raise if strict
        Rails.logger.error(
          "[dns_link] failed remote_host_id=#{remote_host&.id} domain=#{domain} error=#{e.class}: #{e.message}"
        )
      end
    end
  end
end
