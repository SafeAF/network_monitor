# frozen_string_literal: true

require "rails_helper"

RSpec.describe Netmon::Anomaly::DeviceStats do
  it "counts distinct new destinations and excludes future or expired observations" do
    now = Time.current.change(sec: 0)
    device = Device.create!(ip: "10.0.0.20", name: "client", first_seen_at: now, last_seen_at: now)
    DeviceMinute.create!(device_id: device.id, bucket_ts: now, uplink_bytes: 100, new_dst_ips: 99)
    DeviceMinute.create!(device_id: device.id, bucket_ts: now + 1.minute, uplink_bytes: 900)
    DeviceMinute.create!(device_id: device.id, bucket_ts: now - 11.minutes, uplink_bytes: 900)
    [["203.0.113.8", now, now], ["203.0.113.8", now, now],
      ["203.0.113.9", now + 1.minute, now + 1.minute],
      ["203.0.113.10", now - 11.minutes, now - 11.minutes],
      ["203.0.113.11", now - 1.day, now]].each_with_index do |(ip, first, last), index|
      RemoteHost.find_or_create_by!(ip: ip) do |host|
        host.first_seen_at = first
        host.last_seen_at = last
      end
      Connection.create!(proto: "tcp", src_ip: device.ip, src_port: index + 1, dst_ip: ip,
        dst_port: 443, first_seen_at: first, last_seen_at: last)
    end

    stats = described_class.current(device.id, now: now)
    expect(stats.uplink_bytes_last_10m).to eq(100)
    expect(stats.new_dst_ips_last_10m).to eq(1)
    expect(stats.unique_dst_ips_last_10m).to eq(2)
  end
end
