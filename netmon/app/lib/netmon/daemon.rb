# frozen_string_literal: true

module Netmon
  class Daemon
    def self.run(interval: 1.0, input_file: ENV["CONNTRACK_INPUT_FILE"], max_iterations: nil, metrics_recorder: Netmon::MetricsRecorder)
      iterations = 0
      loop do
        begin
          Netmon::ReconcileSnapshot.run(input_file:)
          metrics_recorder&.record_if_due
        rescue StandardError => e
          Rails.logger.error("netmon daemon error: #{e.class}: #{e.message}")
        end

        iterations += 1
        break if max_iterations && iterations >= max_iterations

        sleep interval
      end
    end
  end
end
