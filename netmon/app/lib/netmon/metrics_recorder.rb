# frozen_string_literal: true

module Netmon
  class MetricsRecorder
    SAMPLE_INTERVAL = 60.seconds
    BASELINE_WINDOW = 7.days

    def self.record_if_due(now: Time.current)
      last_sample = MetricSample.order(captured_at: :desc).limit(1).pick(:captured_at)
      return if last_sample && last_sample >= now - SAMPLE_INTERVAL

      record!(now:)
    end

    def self.record!(now: Time.current)
      sample = build_sample(now:)
      MetricSample.create!(sample)
      sample
    end

    def self.build_sample(now: Time.current)
      window_10m = now - 10.minutes
      window_1h = now - 1.hour

      new_dst_ips_last_10m = RemoteHost.where("first_seen_at >= ?", window_10m).count
      unique_dports_last_10m = Connection.where("last_seen_at >= ?", window_10m)
                                         .where.not(dst_port: nil)
                                         .distinct
                                         .count(:dst_port)
      uplink_bytes_last_10m = Connection.where("last_seen_at >= ?", window_10m)
                                        .sum(:uplink_bytes)

      new_asns_last_1h = if RemoteHost.column_names.include?("whois_asn")
                           RemoteHost.where("first_seen_at >= ?", window_1h)
                                     .where.not(whois_asn: nil)
                                     .distinct
                                     .count(:whois_asn)
                         else
                           0
                         end

      baseline_p95 = baseline_p95_uplink(now:)

      {
        captured_at: now,
        new_dst_ips_last_10m:,
        unique_dports_last_10m:,
        uplink_bytes_last_10m:,
        baseline_p95_uplink_bytes_last_10m: baseline_p95,
        new_asns_last_1h:
      }
    end

    def self.baseline_p95_uplink(now:)
      window_start = now - BASELINE_WINDOW
      values = MetricSample.where("captured_at >= ?", window_start)
                           .order(captured_at: :desc)
                           .limit(2000)
                           .pluck(:uplink_bytes_last_10m)
      percentile(values, 0.95)
    end
    private_class_method :baseline_p95_uplink

    def self.percentile(values, p)
      return 0 if values.empty?

      sorted = values.sort
      rank = (p * (sorted.length - 1)).round
      sorted[rank].to_i
    end
    private_class_method :percentile
  end
end
