# frozen_string_literal: true

require "yaml"

module Netmon
  module Anomaly
    class Scorer
      Reason = Struct.new(:code, :weight, :detail, keyword_init: true)

      def self.score_connection(connection:, device:, remote_host:, baseline:, device_stats:, now: Time.current, config: nil)
        config ||= load_config
        common_ports = Array(config["common_ports"].presence || [53, 80, 123, 443]).map(&:to_i)
        common_protos = Array(config["common_protos"].presence || %w[tcp udp]).map(&:downcase)
        new_window_seconds = (config["new_window_seconds"].presence || 600).to_i
        dormant_days = (config["dormant_remote_days"].presence || 30).to_i
        high_fanout_threshold = (config["high_fanout_threshold"].presence || 30).to_i
        high_unique_ports_threshold = (config["high_unique_ports_threshold"].presence || 20).to_i

        reasons = []

        if remote_host&.first_seen_at && remote_host.first_seen_at >= now - new_window_seconds
          reasons << Reason.new(code: "NEW_DST", weight: 30, detail: remote_host.ip)
        end

        if remote_host&.last_seen_at && remote_host.last_seen_at < now - dormant_days.days
          reasons << Reason.new(code: "DORMANT_DST", weight: 15, detail: remote_host.ip)
        end

        if new_asn?(device, remote_host, now: now)
          reasons << Reason.new(code: "NEW_ASN", weight: 20, detail: remote_host&.whois_asn || remote_host&.whois_name)
        end

        if connection.dst_port && !common_ports.include?(connection.dst_port.to_i)
          if connection.proto.to_s.downcase == "udp" && connection.dst_port.to_i == 443
            reasons << Reason.new(code: "RARE_PORT", weight: 5, detail: connection.dst_port)
          else
            reasons << Reason.new(code: "RARE_PORT", weight: 25, detail: connection.dst_port)
          end
        end

        if connection.proto.to_s.downcase.present? && !common_protos.include?(connection.proto.to_s.downcase)
          reasons << Reason.new(code: "UNEXPECTED_PROTO", weight: 20, detail: connection.proto)
        end

        if remote_host && remote_host.rdns_name.to_s.strip.empty?
          reasons << Reason.new(code: "NO_RDNS", weight: 10, detail: remote_host.ip)
        end

        if baseline && baseline.p95_uplink_bytes_per_min.to_i > 0
          threshold = baseline.p95_uplink_bytes_per_min.to_i * 10 * 3
          if device_stats.uplink_bytes_last_10m.to_i > threshold
            reasons << Reason.new(code: "HIGH_EGRESS", weight: 25, detail: device_stats.uplink_bytes_last_10m)
          end
        end

        fanout_threshold = [baseline&.p95_new_dst_ips_per_10m.to_i * 3, high_fanout_threshold].max
        if device_stats.new_dst_ips_last_10m.to_i > fanout_threshold
          reasons << Reason.new(code: "HIGH_FANOUT", weight: 25, detail: device_stats.new_dst_ips_last_10m)
        end

        ports_threshold = [baseline&.p95_unique_ports_per_10m.to_i * 3, high_unique_ports_threshold].max
        if device_stats.unique_ports_last_10m.to_i > ports_threshold
          reasons << Reason.new(code: "PORT_SCAN_LIKE", weight: 25, detail: device_stats.unique_ports_last_10m)
        end

        score = reasons.sum(&:weight)
        score = [[score, 0].max, 100].min

        {
          score: score,
          reasons: reasons.map { |r| { code: r.code, weight: r.weight, detail: r.detail } }
        }
      end

      def self.new_asn?(device, remote_host, now: Time.current)
        return false unless device && remote_host

        asn = remote_host.whois_asn.presence || remote_host.whois_name.presence
        return false if asn.nil?

        window_start = now - 7.days
        seen = Connection.joins("INNER JOIN remote_hosts ON remote_hosts.ip = connections.dst_ip")
                  .where(src_ip: device.ip)
                  .where("connections.last_seen_at >= ?", window_start)
                  .where("remote_hosts.whois_asn = ? OR remote_hosts.whois_name = ?", asn, asn)
                  .exists?
        !seen
      end
      private_class_method :new_asn?

      def self.load_config
        path = Rails.root.join("config/netmon.yml")
        YAML.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: false) || {}
      rescue Errno::ENOENT
        {}
      end
      private_class_method :load_config
    end
  end
end
