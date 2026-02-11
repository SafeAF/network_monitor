# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Incident grouping" do
  include ActiveSupport::Testing::TimeHelpers

  let(:device) do
    Device.create!(
      ip: "10.0.0.24",
      name: "Desktop",
      first_seen_at: Time.current - 1.day,
      last_seen_at: Time.current
    )
  end

  let(:remote_host) do
    RemoteHost.create!(
      ip: "203.0.113.10",
      first_seen_at: Time.current - 5.minutes,
      last_seen_at: Time.current,
      rdns_name: nil,
      whois_asn: "AS64512",
      tag: "unknown"
    )
  end

  let(:connection) do
    Connection.create!(
      proto: "tcp",
      src_ip: device.ip,
      src_port: 1234,
      dst_ip: remote_host.ip,
      dst_port: 4444,
      uplink_packets: 1,
      uplink_bytes: 100,
      downlink_packets: 1,
      downlink_bytes: 50,
      first_seen_at: Time.current - 5.minutes,
      last_seen_at: Time.current - 5.minutes,
      anomaly_score: 80,
      anomaly_reasons_json: "[]"
    )
  end

  let(:alert_config) do
    {
      "threshold_score" => 70,
      "required_codes" => ["RARE_PORT"],
      "suppress_if_only_codes" => ["NO_RDNS"],
      "incident_window_seconds" => 600
    }
  end

  it "updates the same incident within the window" do
    travel_to(Time.zone.parse("2026-02-06 12:00:00")) do
      reasons = [{ code: "RARE_PORT", weight: 25 }]
      Netmon::ReconcileSnapshot.send(
        :emit_anomaly_hit,
        connection: connection,
        device: device,
        remote_host: remote_host,
        reasons: reasons,
        now: Time.current,
        dedup_seconds: 1,
        alert_config: alert_config,
        incident_window_seconds: 600
      )

      travel 2.seconds

      Netmon::ReconcileSnapshot.send(
        :emit_anomaly_hit,
        connection: connection,
        device: device,
        remote_host: remote_host,
        reasons: reasons,
        now: Time.current,
        dedup_seconds: 1,
        alert_config: alert_config,
        incident_window_seconds: 600
      )
    end

    incident = Incident.first
    expect(Incident.count).to eq(1)
    expect(incident.count).to eq(2)
  end

  it "creates a new incident after the window" do
    travel_to(Time.zone.parse("2026-02-06 12:00:00")) do
      reasons = [{ code: "RARE_PORT", weight: 25 }]
      Netmon::ReconcileSnapshot.send(
        :emit_anomaly_hit,
        connection: connection,
        device: device,
        remote_host: remote_host,
        reasons: reasons,
        now: Time.current,
        dedup_seconds: 1,
        alert_config: alert_config,
        incident_window_seconds: 600
      )

      travel 700.seconds

      Netmon::ReconcileSnapshot.send(
        :emit_anomaly_hit,
        connection: connection,
        device: device,
        remote_host: remote_host,
        reasons: reasons,
        now: Time.current,
        dedup_seconds: 1,
        alert_config: alert_config,
        incident_window_seconds: 600
      )
    end

    expect(Incident.count).to eq(2)
  end

  it "suppresses NO_RDNS-only incidents" do
    travel_to(Time.zone.parse("2026-02-06 12:00:00")) do
      reasons = [{ code: "NO_RDNS", weight: 10 }]
      connection.update!(anomaly_score: 90)
      Netmon::ReconcileSnapshot.send(
        :emit_anomaly_hit,
        connection: connection,
        device: device,
        remote_host: remote_host,
        reasons: reasons,
        now: Time.current,
        dedup_seconds: 1,
        alert_config: alert_config,
        incident_window_seconds: 600
      )
    end

    expect(Incident.count).to eq(0)
  end
end
