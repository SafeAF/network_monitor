# frozen_string_literal: true

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
        anomalies:
      }
    end

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
