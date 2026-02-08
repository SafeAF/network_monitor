# frozen_string_literal: true

require "rails_helper"

RSpec.describe Netmon::Baseline::Recompute do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    Time.zone = "UTC"
    travel_to(Time.zone.parse("2026-02-06 12:00:00")) { example.run }
  end

  it "computes p95 baselines from device minutes" do
    device = Device.create!(
      ip: "10.0.0.24",
      name: "Desktop",
      first_seen_at: Time.current - 1.day,
      last_seen_at: Time.current
    )

    base_ts = Time.current - 20.minutes
    10.times do |i|
      DeviceMinute.create!(
        device_id: device.id,
        bucket_ts: base_ts + i.minutes,
        uplink_bytes: (i + 1) * 100,
        conn_count: i + 1,
        new_dst_ips: i,
        unique_dst_ports: i * 2
      )
    end

    described_class.run(now: Time.current)

    baseline = DeviceBaseline.find_by(device_id: device.id)
    expect(baseline).not_to be_nil
    expect(baseline.p95_uplink_bytes_per_min).to eq(1000)
    expect(baseline.p95_conn_count_per_min).to eq(10)
    expect(baseline.p95_new_dst_ips_per_10m).to be >= 9
    expect(baseline.p95_unique_ports_per_10m).to be >= 18
  end
end
