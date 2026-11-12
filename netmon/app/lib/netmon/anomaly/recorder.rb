# frozen_string_literal: true

module Netmon
  module Anomaly
    class Recorder
      DEVICE_CODES = %w[HIGH_FANOUT PORT_SCAN_LIKE].freeze

      def self.call(connection:, device:, remote_host:, reasons:, now:, config:)
        alert = config.fetch("alert", {})
        dedup = (config["dedup_suppress_seconds"].presence || 600).to_i
        window = (alert["incident_window_seconds"].presence || 600).to_i
        threshold = (config["anomaly_threshold"].presence || 50).to_i
        codes = codes_for(reasons)
        return if (codes & DEVICE_CODES).empty? && connection.anomaly_score.to_i < threshold

        AnomalyHit.transaction do
          # Acquire a write lock before cooldown reads. SQLite ignores SELECT
          # FOR UPDATE; this also serializes recording against other workers.
          Device.where(id: device.id).update_all("updated_at = updated_at")
          (codes & DEVICE_CODES).each do |code|
            score = (alert["threshold_score"].presence || 70).to_i
            device_reasons = [{ code: code, weight: 25, detail: "device-level" }]
            record_hit(device: device, remote_host: nil, connection: nil, reasons: device_reasons,
              score: score, fingerprint: ["DEVICE", device.id, code].join("|"),
              now: now, dedup: dedup, window: window, alert: alert)
          end
          if connection.anomaly_score.to_i >= threshold
            fingerprint = [device.id, connection.dst_ip, connection.dst_port, connection.proto, codes.join(",")].join("|")
            record_hit(device: device, remote_host: remote_host, connection: connection, reasons: reasons,
              score: connection.anomaly_score.to_i, fingerprint: fingerprint,
              now: now, dedup: dedup, window: window, alert: alert)
          end
        end
      end

      def self.record_hit(device:, remote_host:, connection:, reasons:, score:, fingerprint:, now:, dedup:, window:, alert:)
        # Symmetric event-time cooldowns also cover observations arriving late.
        return if AnomalyHit.where(fingerprint: fingerprint).where(occurred_at: (now - dedup)..(now + dedup)).exists?

        codes = codes_for(reasons)
        policy = AlertPolicy.evaluate(reasons: reasons, score: score, config: { "alert" => alert })
        hit = AnomalyHit.create!(
          occurred_at: now, device_id: device.id, remote_host_id: remote_host&.id,
          proto: connection&.proto, src_ip: device.ip, dst_ip: connection&.dst_ip, dst_port: connection&.dst_port,
          score: score, total_bytes: connection ? connection.uplink_bytes.to_i + connection.downlink_bytes.to_i : 0,
          summary: codes.join(","), reasons_json: reasons.to_json,
          fingerprint: fingerprint, suppressed_until: now + dedup, alertable: policy.alertable
        )
        return unless policy.alertable

        incident_codes = (policy.codes - policy.suppress_only_codes).uniq.sort
        incident_fingerprint = IncidentFingerprint.build(
          device_id: device.id, dst_ip: connection&.dst_ip, dst_port: connection&.dst_port,
          proto: connection&.proto, codes: incident_codes,
          required_codes: policy.required_codes, suppress_codes: policy.suppress_only_codes
        )
        incident = Incident.where(fingerprint: incident_fingerprint)
          .where("first_seen_at <= ? AND last_seen_at >= ?", now + window, now - window)
          .order(last_seen_at: :desc).first
        if incident
          incident.update!(
            first_seen_at: [incident.first_seen_at, now].min,
            last_seen_at: [incident.last_seen_at, now].max,
            count: incident.count.to_i + 1,
            max_score: [incident.max_score.to_i, score].max,
            codes_csv: (incident.codes_csv.to_s.split(",") + incident_codes).uniq.sort.join(",")
          )
        else
          incident = Incident.create!(
            fingerprint: incident_fingerprint, device_id: device.id, dst_ip: connection&.dst_ip,
            dst_port: connection&.dst_port, proto: connection&.proto, codes_csv: incident_codes.join(","),
            first_seen_at: now, last_seen_at: now, count: 1, max_score: score
          )
        end
        hit.update!(incident_id: incident.id)
      end
      private_class_method :record_hit

      def self.codes_for(reasons)
        Array(reasons).filter_map { |reason| reason[:code] || reason["code"] }.map(&:to_s).uniq.sort
      end
      private_class_method :codes_for
    end
  end
end
