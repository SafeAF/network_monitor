# frozen_string_literal: true

require "rails_helper"

RSpec.describe Netmon::ReconcileSnapshot do
  let(:fixture_path) { "spec/fixtures/conntrack/router_extended.txt" }

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
