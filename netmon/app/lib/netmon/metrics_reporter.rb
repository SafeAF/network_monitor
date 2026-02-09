# frozen_string_literal: true

require "yaml"

module Netmon
  class MetricsReporter
    def self.current(now: Time.current)
      window_10m = now - 10.minutes
      window_1h = now - 1.hour

      new_dst_ips_last_10m = RemoteHost.where("first_seen_at >= ?", window_10m).count
      unique_dports_last_10m = Connection.where("last_seen_at >= ?", window_10m)
                                         .where.not(dst_port: nil)
                                         .distinct
                                         .count(:dst_port)
      uplink_bytes_last_10m = Connection.where("last_seen_at >= ?", window_10m).sum(:uplink_bytes)
      baseline_p95 = Netmon::MetricsRecorder.send(:baseline_p95_uplink, now:)

      if RemoteHost.column_names.include?("whois_asn")
        new_asns_last_1h = RemoteHost.where("first_seen_at >= ?", window_1h)
                                     .where.not(whois_asn: nil)
                                     .distinct
                                     .count(:whois_asn)
        new_asns_list = RemoteHost.where("first_seen_at >= ?", window_1h)
                                  .where.not(whois_asn: nil)
                                  .distinct
                                  .pluck(:whois_asn)
      else
        new_asns_last_1h = 0
        new_asns_list = []
      end

      new_dst_hosts = RemoteHost.where("first_seen_at >= ?", window_10m)
                                .order(first_seen_at: :desc)
                                .limit(50)
                                .map { |host| host_payload(host) }

      config = load_config
      common_ports = Array(config["common_ports"].presence || [53, 80, 123, 443]).map(&:to_i)
      top_ports = Connection.where("last_seen_at >= ?", window_10m)
                            .where.not(dst_port: nil)
                            .group(:dst_port)
                            .order(Arel.sql("COUNT(*) DESC"))
                            .limit(10)
                            .count

      unique_dports_hosts = top_ports.map do |port, count|
        ips = Connection.where("last_seen_at >= ?", window_10m)
                        .where(dst_port: port)
                        .distinct
                        .limit(50)
                        .pluck(:dst_ip)
        hosts = RemoteHost.where(ip: ips).map { |host| host_payload(host) }
        { port: port, count: count, hosts: hosts }
      end

      rare_ports_24h = Connection.where("last_seen_at >= ?", now - 24.hours)
                                 .where.not(dst_port: nil)
                                 .where.not(dst_port: common_ports)
                                 .group(:dst_port)
                                 .order(Arel.sql("COUNT(*) DESC"))
                                 .limit(10)
                                 .count

      rare_ports_hosts = rare_ports_24h.map do |port, count|
        ips = Connection.where("last_seen_at >= ?", now - 24.hours)
                        .where(dst_port: port)
                        .distinct
                        .limit(50)
                        .pluck(:dst_ip)
        hosts = RemoteHost.where(ip: ips).map { |host| host_payload(host) }
        { port: port, count: count, hosts: hosts }
      end

      new_asns_hosts = if RemoteHost.column_names.include?("whois_asn")
                         RemoteHost.where("first_seen_at >= ?", window_1h)
                                   .where.not(whois_asn: nil)
                                   .group(:whois_asn)
                                   .order(Arel.sql("MAX(first_seen_at) DESC"))
                                   .limit(10)
                                   .pluck(:whois_asn)
                                   .map do |asn|
                                     hosts = RemoteHost.where("first_seen_at >= ?", window_1h)
                                                       .where(whois_asn: asn)
                                                       .order(first_seen_at: :desc)
                                                       .limit(50)
                                                       .map { |host| host_payload(host) }
                                     { asn: asn, hosts: hosts }
                                   end
                       else
                         []
                       end

      anomalies = []
      if new_dst_ips_last_10m > 50
        anomalies << { rule: "new_dst_ips_last_10m > 50", level: "suspicious" }
      end
      if unique_dports_last_10m > 20
        anomalies << { rule: "unique_dports_last_10m > 20", level: "suspicious" }
      end
      if baseline_p95.positive? && uplink_bytes_last_10m > baseline_p95 * 3
        anomalies << { rule: "uplink_bytes_last_10m > baseline_p95 * 3", level: "suspicious" }
      end
      if new_asns_last_1h > 10
        anomalies << { rule: "new_asns_last_1h > 10", level: "suspicious" }
      end

      {
        new_dst_ips_last_10m:,
        unique_dports_last_10m:,
        uplink_bytes_last_10m:,
        baseline_p95_uplink_bytes_last_10m: baseline_p95,
        new_asns_last_1h:,
        new_asns_list:,
        new_dst_hosts:,
        unique_dports_hosts:,
        new_asns_hosts:,
        rare_ports_hosts:,
        anomalies:
      }
    end

    def self.host_payload(host)
      {
        ip: host.ip,
        rdns: host.rdns_name,
        whois: host.whois_name,
        whois_raw: host.respond_to?(:whois_raw_line) ? host.whois_raw_line : nil
      }
    end
    private_class_method :host_payload

    def self.load_config
      path = Rails.root.join("config/netmon.yml")
      YAML.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: false) || {}
    rescue Errno::ENOENT
      {}
    end
    private_class_method :load_config

    def self.series(limit: 120)
      samples = MetricSample.order(captured_at: :desc).limit(limit).reverse
      {
        timestamps: samples.map { |s| s.captured_at.iso8601 },
        new_dst_ips_last_10m: samples.map(&:new_dst_ips_last_10m),
        unique_dports_last_10m: samples.map(&:unique_dports_last_10m),
        uplink_bytes_last_10m: samples.map(&:uplink_bytes_last_10m),
        baseline_p95_uplink_bytes_last_10m: samples.map(&:baseline_p95_uplink_bytes_last_10m),
        new_asns_last_1h: samples.map(&:new_asns_last_1h)
      }
    end
  end
end
