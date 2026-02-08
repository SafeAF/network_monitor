# frozen_string_literal: true

require "rails_helper"

RSpec.describe Netmon::MetricsReporter do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    Time.zone = "UTC"
    travel_to(Time.zone.parse("2026-02-06 12:00:00")) { example.run }
  end

  it "returns analytics and anomalies based on thresholds" do
    RemoteHost.create!(ip: "203.0.113.10", first_seen_at: Time.current - 60, last_seen_at: Time.current, whois_asn: "AS64512")
    RemoteHost.create!(ip: "203.0.113.11", first_seen_at: Time.current - 60, last_seen_at: Time.current, whois_asn: "AS64513")
    RemoteHost.create!(ip: "203.0.113.12", first_seen_at: Time.current - 60, last_seen_at: Time.current, whois_asn: "AS64514")
    Connection.create!(
      proto: "tcp",
      src_ip: "10.0.0.24",
      src_port: 1234,
      dst_ip: "203.0.113.10",
      dst_port: 443,
      uplink_packets: 1,
      uplink_bytes: 10_000,
      downlink_packets: 1,
      downlink_bytes: 100,
      first_seen_at: Time.current - 60,
      last_seen_at: Time.current - 60
    )

    MetricSample.create!(captured_at: Time.current - 10.minutes, uplink_bytes_last_10m: 100)

    analytics = described_class.current(now: Time.current)

    expect(analytics[:new_dst_ips_last_10m]).to eq(3)
    expect(analytics[:new_asns_last_1h]).to eq(3)
    expect(analytics[:anomalies]).to be_an(Array)
  end

  it "returns series data from metric samples" do
    MetricSample.create!(captured_at: Time.current - 2.minutes, uplink_bytes_last_10m: 10)
    MetricSample.create!(captured_at: Time.current - 1.minute, uplink_bytes_last_10m: 20)

    series = described_class.series(limit: 2)

    expect(series[:timestamps].length).to eq(2)
    expect(series[:uplink_bytes_last_10m]).to eq([10, 20])
  end
end
