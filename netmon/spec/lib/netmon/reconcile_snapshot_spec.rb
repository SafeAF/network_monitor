# frozen_string_literal: true

require "rails_helper"

RSpec.describe Netmon::ReconcileSnapshot do
  let(:fixture_path) { "spec/fixtures/conntrack/router_extended.txt" }
  let(:entry_proto) { "tcp" }

  def build_entry(src:, dst:, sport:, dport:, up_bytes:, up_packets:, dn_bytes:, dn_packets:)
    orig = Conntrack::Tuple.new(src:, dst:, sport:, dport:, bytes: up_bytes, packets: up_packets)
    reply = Conntrack::Tuple.new(src: dst, dst: src, sport: dport, dport: sport, bytes: dn_bytes, packets: dn_packets)
    Conntrack::Entry.new(
      family: "ipv4",
      proto: entry_proto,
      timeout: 60,
      state: "ESTABLISHED",
      orig:,
      reply:,
      flags: [],
      mark: 0,
      use: 0
    )
  end

  it "upserts remote hosts and connections from snapshot" do
    now = Time.zone.parse("2026-02-03 12:00:00")

    allow(Netmon::HostEnricher).to receive(:apply)

    result = described_class.run(input_file: fixture_path, now: now)

    expect(result.remote_hosts_upserted).to be > 0
    expect(result.connections_upserted).to be > 0
    expect(RemoteHost.exists?(ip: "192.82.242.219")).to eq(true)
    expect(RemoteHost.exists?(ip: "10.0.0.1")).to eq(false)
    expect(Connection.count).to be > 0
  end

  it "creates and updates minute buckets with delta attribution" do
    now = Time.zone.parse("2026-02-03 12:00:10")
    later = now + 20

    allow(Netmon::HostEnricher).to receive(:apply)

    first_entry = build_entry(
      src: "10.0.0.24",
      dst: "203.0.113.10",
      sport: 4000,
      dport: 443,
      up_bytes: 100,
      up_packets: 10,
      dn_bytes: 50,
      dn_packets: 5
    )
    second_entry = build_entry(
      src: "10.0.0.24",
      dst: "203.0.113.10",
      sport: 4000,
      dport: 443,
      up_bytes: 160,
      up_packets: 18,
      dn_bytes: 90,
      dn_packets: 9
    )

    allow(Conntrack::Snapshot).to receive(:read).and_return([first_entry], [second_entry])

    described_class.run(input_file: nil, now: now)
    described_class.run(input_file: nil, now: later)

    device = Device.find_by(ip: "10.0.0.24")
    remote_host = RemoteHost.find_by(ip: "203.0.113.10")
    bucket_ts = now.utc.change(sec: 0)

    device_minute = DeviceMinute.find_by(device_id: device.id, bucket_ts:)
    remote_minute = RemoteHostMinute.find_by(remote_host_id: remote_host.id, bucket_ts:)

    expect(device_minute).not_to be_nil
    expect(remote_minute).not_to be_nil
    expect(device_minute.conn_count).to eq(2)
    expect(remote_minute.conn_count).to eq(2)

    expect(device_minute.uplink_bytes).to eq(60)
    expect(device_minute.downlink_bytes).to eq(40)
    expect(device_minute.uplink_packets).to eq(8)
    expect(device_minute.downlink_packets).to eq(4)

    expect(device_minute.unique_dst_ips).to eq(1)
    expect(device_minute.unique_dst_ports).to eq(1)
    expect(device_minute.unique_protos).to eq(1)
    expect(device_minute.rare_ports).to eq(0)
    expect(device_minute.new_dst_ips).to eq(1)
  end

  it "dedups anomaly hits within suppression window" do
    now = Time.zone.parse("2026-02-03 12:00:10")
    later = now + 60

    allow(Netmon::HostEnricher).to receive(:apply)

    entry = build_entry(
      src: "10.0.0.24",
      dst: "203.0.113.10",
      sport: 4000,
      dport: 443,
      up_bytes: 100,
      up_packets: 10,
      dn_bytes: 50,
      dn_packets: 5
    )

    allow(Conntrack::Snapshot).to receive(:read).and_return([entry], [entry])
    allow(Netmon::Anomaly::Scorer).to receive(:score_connection).and_return(
      score: 80,
      reasons: [{ code: "NEW_DST", weight: 30 }]
    )
    allow(Netmon::Anomaly::DeviceStats).to receive(:current).and_return(
      Netmon::Anomaly::DeviceStats::Result.new(
        uplink_bytes_last_10m: 0,
        new_dst_ips_last_10m: 0,
        unique_ports_last_10m: 0
      )
    )

    described_class.run(input_file: nil, now: now)
    described_class.run(input_file: nil, now: later)

    expect(AnomalyHit.count).to eq(1)
  end

  it "emits device-level hits for fanout and port scan rules" do
    now = Time.zone.parse("2026-02-03 12:00:10")

    allow(Netmon::HostEnricher).to receive(:apply)

    entry = build_entry(
      src: "10.0.0.24",
      dst: "203.0.113.10",
      sport: 4000,
      dport: 443,
      up_bytes: 100,
      up_packets: 10,
      dn_bytes: 50,
      dn_packets: 5
    )

    allow(Conntrack::Snapshot).to receive(:read).and_return([entry])
    allow(Netmon::Anomaly::Scorer).to receive(:score_connection).and_return(
      score: 10,
      reasons: [
        { code: "HIGH_FANOUT", weight: 25 },
        { code: "PORT_SCAN_LIKE", weight: 25 }
      ]
    )
    allow(Netmon::Anomaly::DeviceStats).to receive(:current).and_return(
      Netmon::Anomaly::DeviceStats::Result.new(
        uplink_bytes_last_10m: 0,
        new_dst_ips_last_10m: 0,
        unique_ports_last_10m: 0
      )
    )

    described_class.run(input_file: nil, now: now)

    summaries = AnomalyHit.pluck(:summary)
    expect(summaries).to include("HIGH_FANOUT", "PORT_SCAN_LIKE")
  end

  it "upserts port history and increments seen_count" do
    now = Time.zone.parse("2026-02-03 12:00:10")
    later = now + 60

    allow(Netmon::HostEnricher).to receive(:apply)

    entry = build_entry(
      src: "10.0.0.24",
      dst: "203.0.113.10",
      sport: 4000,
      dport: 443,
      up_bytes: 100,
      up_packets: 10,
      dn_bytes: 50,
      dn_packets: 5
    )

    allow(Conntrack::Snapshot).to receive(:read).and_return([entry], [entry])

    described_class.run(input_file: nil, now: now)
    described_class.run(input_file: nil, now: later)

    host = RemoteHost.find_by(ip: "203.0.113.10")
    port = RemoteHostPort.find_by(remote_host_id: host.id, dst_port: 443)
    expect(port).not_to be_nil
    expect(port.first_seen_at).to eq(now)
    expect(port.last_seen_at).to eq(later)
    expect(port.seen_count).to eq(2)
  end

  describe ".compute_deltas" do
    it "returns zero deltas for new connections" do
      connection = Connection.new
      deltas = described_class.send(
        :compute_deltas,
        connection,
        cur_up_b: 100,
        cur_dn_b: 50,
        cur_up_p: 10,
        cur_dn_p: 5
      )

      expect(deltas).to eq(d_up_b: 0, d_dn_b: 0, d_up_p: 0, d_dn_p: 0)
    end

    it "clamps negative deltas to zero when counters reset" do
      connection = Connection.new(
        last_uplink_bytes: 200,
        last_downlink_bytes: 150,
        last_uplink_packets: 20,
        last_downlink_packets: 15
      )
      allow(connection).to receive(:new_record?).and_return(false)

      deltas = described_class.send(
        :compute_deltas,
        connection,
        cur_up_b: 50,
        cur_dn_b: 40,
        cur_up_p: 2,
        cur_dn_p: 1
      )

      expect(deltas).to eq(d_up_b: 0, d_dn_b: 0, d_up_p: 0, d_dn_p: 0)
    end

    it "computes positive deltas for existing connections" do
      connection = Connection.new(
        last_uplink_bytes: 200,
        last_downlink_bytes: 150,
        last_uplink_packets: 20,
        last_downlink_packets: 15
      )
      allow(connection).to receive(:new_record?).and_return(false)

      deltas = described_class.send(
        :compute_deltas,
        connection,
        cur_up_b: 260,
        cur_dn_b: 190,
        cur_up_p: 28,
        cur_dn_p: 18
      )

      expect(deltas).to eq(d_up_b: 60, d_dn_b: 40, d_up_p: 8, d_dn_p: 3)
    end
  end

  it "upserts devices from snapshot and updates last_seen_at" do
    now = Time.zone.parse("2026-02-03 12:00:00")
    later = now + 60

    allow(Netmon::HostEnricher).to receive(:apply)

    described_class.run(input_file: fixture_path, now: now)
    device = Device.find_by(ip: "10.0.0.24")
    expect(device).not_to be_nil
    expect(device.first_seen_at).to eq(now)
    expect(device.last_seen_at).to eq(now)

    described_class.run(input_file: fixture_path, now: later)
    device.reload
    expect(device.first_seen_at).to eq(now)
    expect(device.last_seen_at).to eq(later)
  end

  it "deletes connections not present in the latest snapshot" do
    allow(Netmon::HostEnricher).to receive(:apply)
    described_class.run(input_file: fixture_path, now: Time.current)
    expect(Connection.count).to be > 0

    allow(Conntrack::Snapshot).to receive(:read).and_return([])

    result = described_class.run(input_file: nil, now: Time.current)
    expect(result.connections_deleted).to be > 0
    expect(Connection.count).to eq(0)
  end
end
