# frozen_string_literal: true

module Netmon
  module Baseline
    class Recompute
      WINDOW_MINUTES = 60
      LOOKBACK_HOURS = 24

      def self.run(now: Time.current)
        Device.find_each do |device|
          recompute_device(device, now:)
        end
      end

      def self.recompute_device(device, now: Time.current)
        window_start = now - LOOKBACK_HOURS.hours
        minutes = DeviceMinute.where(device_id: device.id)
                              .where("bucket_ts >= ?", window_start)
                              .order(:bucket_ts)
                              .to_a
        uplink_values = minutes.map(&:uplink_bytes)
        conn_values = minutes.map(&:conn_count)
        new_dst_values = rolling_sum(minutes.map(&:new_dst_ips), 10)
        unique_ports_values = rolling_max(minutes.map(&:unique_dst_ports), 10)

        baseline = DeviceBaseline.find_or_initialize_by(device_id: device.id)
        baseline.window_minutes = WINDOW_MINUTES
        baseline.p95_uplink_bytes_per_min = percentile(uplink_values, 0.95)
        baseline.p95_conn_count_per_min = percentile(conn_values, 0.95)
        baseline.p95_new_dst_ips_per_10m = percentile(new_dst_values, 0.95)
        baseline.p95_unique_ports_per_10m = percentile(unique_ports_values, 0.95)
        baseline.updated_at = now
        baseline.save!
      end

      def self.rolling_sum(values, window)
        return [] if values.empty?

        sums = []
        values.each_index do |idx|
          start_idx = [idx - window + 1, 0].max
          sums << values[start_idx..idx].sum
        end
        sums
      end
      private_class_method :rolling_sum

      def self.rolling_max(values, window)
        return [] if values.empty?

        maxes = []
        values.each_index do |idx|
          start_idx = [idx - window + 1, 0].max
          maxes << values[start_idx..idx].max
        end
        maxes
      end
      private_class_method :rolling_max

      def self.percentile(values, p)
        return 0 if values.empty?

        sorted = values.sort
        rank = (p * (sorted.length - 1)).ceil
        sorted[rank].to_i
      end
      private_class_method :percentile
    end
  end
end
