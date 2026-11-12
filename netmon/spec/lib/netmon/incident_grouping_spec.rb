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
      Netmon::Anomaly::Recorder.call(
        connection: connection,
        device: device,
        remote_host: remote_host,
        reasons: reasons,
        now: Time.current,
        config: { "anomaly_threshold" => 0, "dedup_suppress_seconds" => 1, "alert" => alert_config }
      )

      travel 2.seconds

      Netmon::Anomaly::Recorder.call(
        connection: connection,
        device: device,
        remote_host: remote_host,
        reasons: reasons,
        now: Time.current,
        config: { "anomaly_threshold" => 0, "dedup_suppress_seconds" => 1, "alert" => alert_config }
      )
    end

    incident = Incident.first
    expect(Incident.count).to eq(1)
    expect(incident.count).to eq(2)
  end

  it "creates a new incident after the window" do
    travel_to(Time.zone.parse("2026-02-06 12:00:00")) do
      reasons = [{ code: "RARE_PORT", weight: 25 }]
      Netmon::Anomaly::Recorder.call(
        connection: connection,
        device: device,
        remote_host: remote_host,
        reasons: reasons,
        now: Time.current,
        config: { "anomaly_threshold" => 0, "dedup_suppress_seconds" => 1, "alert" => alert_config }
      )

      travel 700.seconds

      Netmon::Anomaly::Recorder.call(
        connection: connection,
        device: device,
        remote_host: remote_host,
        reasons: reasons,
        now: Time.current,
        config: { "anomaly_threshold" => 0, "dedup_suppress_seconds" => 1, "alert" => alert_config }
      )
    end

    expect(Incident.count).to eq(2)
  end

  it "suppresses NO_RDNS-only incidents" do
    travel_to(Time.zone.parse("2026-02-06 12:00:00")) do
      reasons = [{ code: "NO_RDNS", weight: 10 }]
      connection.update!(anomaly_score: 90)
      Netmon::Anomaly::Recorder.call(
        connection: connection,
        device: device,
        remote_host: remote_host,
        reasons: reasons,
        now: Time.current,
        config: { "anomaly_threshold" => 0, "dedup_suppress_seconds" => 1, "alert" => alert_config }
      )
    end

    expect(Incident.count).to eq(0)
  end

  it "extends an incident backwards for a late hit without regressing its last seen time" do
    now = Time.zone.parse("2026-02-06 12:00:00")
    options = { connection: connection, device: device, remote_host: remote_host,
      reasons: [{ code: "RARE_PORT", weight: 25 }],
      config: { "dedup_suppress_seconds" => 1, "alert" => alert_config } }
    Netmon::Anomaly::Recorder.call(**options, now: now)
    Netmon::Anomaly::Recorder.call(**options, now: now - 30.seconds)

    expect(Incident.count).to eq(1)
    expect(Incident.first.attributes.values_at("first_seen_at", "last_seen_at", "count")).to eq([now - 30.seconds, now, 2])
  end

  it "deduplicates nearby late hits but keeps events outside the incident window separate" do
    now = Time.zone.parse("2026-02-06 12:00:00")
    options = { connection: connection, device: device, remote_host: remote_host,
      reasons: [{ code: "RARE_PORT", weight: 25 }],
      config: { "dedup_suppress_seconds" => 60, "alert" => alert_config } }
    Netmon::Anomaly::Recorder.call(**options, now: now)
    Netmon::Anomaly::Recorder.call(**options, now: now - 30.seconds)
    expect(AnomalyHit.count).to eq(1)
    Netmon::Anomaly::Recorder.call(**options, now: now - 700.seconds)

    expect([AnomalyHit.count, Incident.count]).to eq([2, 2])
  end
end
