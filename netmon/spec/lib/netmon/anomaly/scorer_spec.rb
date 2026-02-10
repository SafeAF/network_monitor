# frozen_string_literal: true

require "rails_helper"

RSpec.describe Netmon::Anomaly::Scorer do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    Time.zone = "UTC"
    travel_to(Time.zone.parse("2026-02-06 12:00:00")) { example.run }
  end

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
      last_seen_at: Time.current - 40.days,
      rdns_name: nil,
      whois_asn: "AS64512"
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
      last_seen_at: Time.current - 5.minutes
    )
  end

  it "scores multiple rules and clamps to 100" do
    baseline = DeviceBaseline.create!(
      device_id: device.id,
      window_minutes: 60,
      p95_uplink_bytes_per_min: 1,
      p95_conn_count_per_min: 0,
      p95_new_dst_ips_per_10m: 1,
      p95_unique_ports_per_10m: 1,
      updated_at: Time.current
    )

    stats = Netmon::Anomaly::DeviceStats::Result.new(
      uplink_bytes_last_10m: 1_000,
      new_dst_ips_last_10m: 100,
      unique_ports_last_10m: 100,
      unique_dst_ips_last_10m: 100,
      top_port_share_10m: 0.2
    )

    score = described_class.score_connection(
      connection:,
      device:,
      remote_host:,
      baseline:,
      device_stats: stats,
      now: Time.current,
      config: {
        "common_ports" => [53, 80, 123, 443],
        "common_protos" => ["tcp", "udp"],
        "new_window_seconds" => 600,
        "dormant_remote_days" => 30,
        "high_fanout_threshold" => 30,
        "high_unique_ports_threshold" => 20
      }
    )

    expect(score[:score]).to be <= 100
    expect(score[:reasons].map { |r| r[:code] }).to include("NEW_DST", "DORMANT_DST", "RARE_PORT", "NO_RDNS")
  end

  it "handles UDP 443 as low-weight rare port" do
    connection.update!(proto: "udp", dst_port: 443)
    stats = Netmon::Anomaly::DeviceStats::Result.new(
      uplink_bytes_last_10m: 0,
      new_dst_ips_last_10m: 0,
      unique_ports_last_10m: 0,
      unique_dst_ips_last_10m: 0,
      top_port_share_10m: 1.0
    )

    result = described_class.score_connection(
      connection:,
      device:,
      remote_host:,
      baseline: nil,
      device_stats: stats,
      now: Time.current,
      config: {
        "common_ports" => [53, 80, 123],
        "common_protos" => ["tcp", "udp"],
        "new_window_seconds" => 600,
        "dormant_remote_days" => 30,
        "high_fanout_threshold" => 30,
        "high_unique_ports_threshold" => 20
      }
    )

    rare_port = result[:reasons].find { |r| r[:code] == "RARE_PORT" }
    expect(rare_port[:weight]).to eq(5)
  end

  it "does not trigger PORT_SCAN_LIKE for 443-heavy browsing" do
    stats = Netmon::Anomaly::DeviceStats::Result.new(
      uplink_bytes_last_10m: 0,
      new_dst_ips_last_10m: 30,
      unique_ports_last_10m: 1,
      unique_dst_ips_last_10m: 30,
      top_port_share_10m: 0.95
    )

    result = described_class.score_connection(
      connection:,
      device:,
      remote_host:,
      baseline: nil,
      device_stats: stats,
      now: Time.current,
      config: {
        "common_ports" => [53, 80, 123, 443],
        "common_protos" => ["tcp", "udp"],
        "new_window_seconds" => 600,
        "dormant_remote_days" => 30,
        "high_fanout_threshold" => 30,
        "high_unique_ports_threshold" => 20
      }
    )

    codes = result[:reasons].map { |r| r[:code] }
    expect(codes).not_to include("PORT_SCAN_LIKE")
  end

  it "triggers PORT_SCAN_LIKE for broad scan pattern" do
    stats = Netmon::Anomaly::DeviceStats::Result.new(
      uplink_bytes_last_10m: 0,
      new_dst_ips_last_10m: 50,
      unique_ports_last_10m: 25,
      unique_dst_ips_last_10m: 25,
      top_port_share_10m: 0.5
    )

    result = described_class.score_connection(
      connection:,
      device:,
      remote_host:,
      baseline: nil,
      device_stats: stats,
      now: Time.current,
      config: {
        "common_ports" => [53, 80, 123, 443],
        "common_protos" => ["tcp", "udp"],
        "new_window_seconds" => 600,
        "dormant_remote_days" => 30,
        "high_fanout_threshold" => 30,
        "high_unique_ports_threshold" => 20
      }
    )

    codes = result[:reasons].map { |r| r[:code] }
    expect(codes).to include("PORT_SCAN_LIKE")
  end

  it "suppresses scoring when IP is allowlisted" do
    AllowlistRule.create!(kind: "ip", value: remote_host.ip)
    stats = Netmon::Anomaly::DeviceStats::Result.new(
      uplink_bytes_last_10m: 0,
      new_dst_ips_last_10m: 0,
      unique_ports_last_10m: 0,
      unique_dst_ips_last_10m: 0,
      top_port_share_10m: 1.0
    )

    result = described_class.score_connection(
      connection:,
      device:,
      remote_host:,
      baseline: nil,
      device_stats: stats,
      now: Time.current,
      config: {
        "common_ports" => [53, 80, 123, 443],
        "common_protos" => ["tcp", "udp"],
        "new_window_seconds" => 600,
        "dormant_remote_days" => 30,
        "high_fanout_threshold" => 30,
        "high_unique_ports_threshold" => 20
      }
    )

    expect(result[:score]).to eq(0)
    expect(result[:reasons]).to eq([])
  end

  it "suppresses NO_RDNS when org is allowlisted" do
    AllowlistRule.create!(kind: "org", value: remote_host.whois_name)
    stats = Netmon::Anomaly::DeviceStats::Result.new(
      uplink_bytes_last_10m: 0,
      new_dst_ips_last_10m: 0,
      unique_ports_last_10m: 0,
      unique_dst_ips_last_10m: 0,
      top_port_share_10m: 1.0
    )

    result = described_class.score_connection(
      connection:,
      device:,
      remote_host:,
      baseline: nil,
      device_stats: stats,
      now: Time.current,
      config: {
        "common_ports" => [53, 80, 123, 443],
        "common_protos" => ["tcp", "udp"],
        "new_window_seconds" => 600,
        "dormant_remote_days" => 30,
        "high_fanout_threshold" => 30,
        "high_unique_ports_threshold" => 20
      }
    )

    codes = result[:reasons].map { |r| r[:code] }
    expect(codes).not_to include("NO_RDNS")
  end

  it "suppresses RARE_PORT when device port is allowlisted" do
    AllowlistRule.create!(kind: "device_port", value: connection.dst_port.to_s, device_id: device.id)
    stats = Netmon::Anomaly::DeviceStats::Result.new(
      uplink_bytes_last_10m: 0,
      new_dst_ips_last_10m: 0,
      unique_ports_last_10m: 0,
      unique_dst_ips_last_10m: 0,
      top_port_share_10m: 1.0
    )

    result = described_class.score_connection(
      connection:,
      device:,
      remote_host:,
      baseline: nil,
      device_stats: stats,
      now: Time.current,
      config: {
        "common_ports" => [53, 80, 123, 443],
        "common_protos" => ["tcp", "udp"],
        "new_window_seconds" => 600,
        "dormant_remote_days" => 30,
        "high_fanout_threshold" => 30,
        "high_unique_ports_threshold" => 20
      }
    )

    codes = result[:reasons].map { |r| r[:code] }
    expect(codes).not_to include("RARE_PORT")
  end
end
