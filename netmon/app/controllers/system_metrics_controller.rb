# frozen_string_literal: true

class SystemMetricsController < ApplicationController
  def series
    metric = params[:metric].to_s
    window = params[:window].presence || "10m"
    now = Time.current
    start_time = window_start(window, now)
    bucket_seconds, max_points = bucket_for_window(window)

    samples = SystemMinute.where("bucket_ts >= ?", start_time).order(:bucket_ts)
    buckets = {}
    samples.each do |sample|
      bucket = sample.bucket_ts.to_i / bucket_seconds
      buckets[bucket] = sample
    end

    ordered = buckets.keys.sort.map { |key| buckets[key] }
    ordered = ordered.last(max_points)

    values = ordered.map do |row|
      case metric
      when "loadavg1" then row.loadavg1.to_f
      when "disk_read_bytes" then row.disk_read_bytes.to_i
      when "disk_write_bytes" then row.disk_write_bytes.to_i
      when "rx_bytes" then row.rx_bytes.to_i
      when "tx_bytes" then row.tx_bytes.to_i
      else 0
      end
    end

    render json: { metric: metric, timestamps: ordered.map { |s| s.bucket_ts.iso8601 }, values: values }
  end

  private

  def window_start(window, now)
    case window
    when "10m" then now - 10.minutes
    when "1h" then now - 1.hour
    when "24h" then now - 24.hours
    when "7d", "1w" then now - 7.days
    else now - 10.minutes
    end
  end

  def bucket_for_window(window)
    case window
    when "10m" then [60, 10]
    when "1h" then [60, 60]
    when "24h" then [300, 288]
    when "7d", "1w" then [1800, 336]
    else [60, 10]
    end
  end
end
