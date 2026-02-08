# frozen_string_literal: true

require "rails_helper"

RSpec.describe Netmon::MetricsRecorder do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    Time.zone = "UTC"
    travel_to(Time.zone.parse("2026-02-06 12:00:00")) { example.run }
  end

  it "records a sample when due" do
    expect do
      described_class.record_if_due
    end.to change(MetricSample, :count).by(1)
  end

  it "does not record a sample if within the interval" do
    described_class.record_if_due

    expect do
      described_class.record_if_due
    end.not_to change(MetricSample, :count)
  end

  it "computes baseline p95 from existing samples" do
    values = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
    values.each_with_index do |value, idx|
      MetricSample.create!(
        captured_at: Time.current - idx.minutes,
        uplink_bytes_last_10m: value
      )
    end

    p95 = described_class.send(:baseline_p95_uplink, now: Time.current)

    expect(p95).to eq(100)
  end

  it "uses current connection totals for uplink_bytes_last_10m" do
    Connection.create!(
      proto: "tcp",
      src_ip: "10.0.0.24",
      src_port: 1111,
      dst_ip: "203.0.113.10",
      dst_port: 443,
      uplink_packets: 1,
      uplink_bytes: 500,
      downlink_packets: 1,
      downlink_bytes: 200,
      first_seen_at: Time.current - 30,
      last_seen_at: Time.current - 30
    )
    Connection.create!(
      proto: "tcp",
      src_ip: "10.0.0.24",
      src_port: 2222,
      dst_ip: "203.0.113.11",
      dst_port: 443,
      uplink_packets: 1,
      uplink_bytes: 800,
      downlink_packets: 1,
      downlink_bytes: 200,
      first_seen_at: Time.current - 30,
      last_seen_at: Time.current - 30
    )

    sample = described_class.record!(now: Time.current)

    expect(sample.uplink_bytes_last_10m).to eq(1300)
  end
end
