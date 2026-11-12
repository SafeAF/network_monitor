# frozen_string_literal: true

module Netmon
  module Anomaly
    class Detection
      def self.call(connection:, device:, remote_host:, now:, config: Scorer.configuration)
        Connection.transaction do
          stats = DeviceStats.current(device.id, device_ip: device.ip, now: now)
          anomaly = Scorer.score_connection(
            connection: connection, device: device, remote_host: remote_host,
            baseline: DeviceBaseline.find_by(device_id: device.id), device_stats: stats,
            now: now, config: config
          )
          connection.update!(anomaly_score: anomaly[:score], anomaly_reasons_json: anomaly[:reasons].to_json)
          Recorder.call(connection: connection, device: device, remote_host: remote_host,
            reasons: anomaly[:reasons], now: now, config: config)
          anomaly
        end
      end
    end
  end
end
