# frozen_string_literal: true

module Netmon
  module Anomaly
    class DeviceStats
      Result = Struct.new(
        :uplink_bytes_last_10m,
        :new_dst_ips_last_10m,
        :unique_ports_last_10m,
        :unique_dst_ips_last_10m,
        :top_port_share_10m,
        keyword_init: true
      )

      WINDOW_MINUTES = 10

      def self.current(device_id, now: Time.current)
        window_start = now - WINDOW_MINUTES.minutes
        minutes = DeviceMinute.where(device_id:)
                              .where("bucket_ts >= ?", window_start)
                              .order(:bucket_ts)

        conn_scope = Connection.where("last_seen_at >= ?", window_start)
                               .where(src_ip: Device.where(id: device_id).select(:ip))

        unique_ports = conn_scope.where.not(dst_port: nil).distinct.count(:dst_port)
        unique_ips = conn_scope.distinct.count(:dst_ip)
        total_count = conn_scope.count
        top_port_count = conn_scope.where.not(dst_port: nil)
                                   .group(:dst_port)
                                   .order(Arel.sql("COUNT(*) DESC"))
                                   .limit(1)
                                   .count
                                   .values
                                   .first.to_i
        top_port_share = total_count.positive? ? (top_port_count.to_f / total_count) : 0.0

        Result.new(
          uplink_bytes_last_10m: minutes.sum(:uplink_bytes),
          new_dst_ips_last_10m: minutes.sum(:new_dst_ips),
          unique_ports_last_10m: unique_ports,
          unique_dst_ips_last_10m: unique_ips,
          top_port_share_10m: top_port_share
        )
      end
    end
  end
end
