# frozen_string_literal: true

module Netmon
  module Anomaly
    class DeviceStats
      Result = Struct.new(
        :uplink_bytes_last_10m,
        :new_dst_ips_last_10m,
        :unique_ports_last_10m,
        keyword_init: true
      )

      WINDOW_MINUTES = 10

      def self.current(device_id, now: Time.current)
        window_start = now - WINDOW_MINUTES.minutes
        minutes = DeviceMinute.where(device_id:)
                              .where("bucket_ts >= ?", window_start)
                              .order(:bucket_ts)
        Result.new(
          uplink_bytes_last_10m: minutes.sum(:uplink_bytes),
          new_dst_ips_last_10m: minutes.sum(:new_dst_ips),
          unique_ports_last_10m: minutes.maximum(:unique_dst_ports) || 0
        )
      end
    end
  end
end
