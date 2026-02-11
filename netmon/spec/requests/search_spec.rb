# frozen_string_literal: true

require "rails_helper"
require "benchmark"

RSpec.describe "Search pages", type: :request do
  it "renders hosts search" do
    get "/search/hosts"
    expect(response).to have_http_status(:ok)
  end

  it "renders connections search" do
    get "/search/connections"
    expect(response).to have_http_status(:ok)
  end

  it "renders anomalies search" do
    get "/search/anomalies"
    expect(response).to have_http_status(:ok)
  end

  it "responds quickly for hosts search with seeded data" do
    now = Time.current
    hosts = (1..250).map do |idx|
      {
        ip: "203.0.113.#{idx}",
        first_seen_at: now - 1.hour,
        last_seen_at: now,
        created_at: now,
        updated_at: now
      }
    end
    RemoteHost.insert_all!(hosts)

    elapsed = Benchmark.realtime { get "/search/hosts" }
    expect(response).to have_http_status(:ok)
    expect(elapsed).to be < 2.0
  end

  it "responds quickly for connections search with seeded data" do
    now = Time.current
    rows = (1..250).map do |idx|
      {
        proto: "tcp",
        src_ip: "10.0.0.#{idx % 200 + 1}",
        src_port: 50_000 + idx,
        dst_ip: "198.51.100.#{idx % 200 + 1}",
        dst_port: 443,
        state: "ESTABLISHED",
        flags: "[ASSURED]",
        uplink_packets: 10,
        uplink_bytes: 1000,
        downlink_packets: 8,
        downlink_bytes: 900,
        first_seen_at: now - 5.minutes,
        last_seen_at: now,
        last_uplink_bytes: 1000,
        last_downlink_bytes: 900,
        last_uplink_packets: 10,
        last_downlink_packets: 8,
        last_delta_at: now,
        anomaly_score: 0,
        anomaly_reasons_json: "[]",
        created_at: now,
        updated_at: now
      }
    end
    Connection.insert_all!(rows)

    elapsed = Benchmark.realtime { get "/search/connections" }
    expect(response).to have_http_status(:ok)
    expect(elapsed).to be < 2.0
  end

  it "responds quickly for anomalies search with seeded data" do
    now = Time.current
    device = Device.create!(
      ip: "10.0.0.42",
      name: "TestDevice",
      first_seen_at: now - 1.day,
      last_seen_at: now
    )
    hits = (1..250).map do |idx|
      {
        occurred_at: now - idx.minutes,
        device_id: device.id,
        dst_ip: "203.0.113.#{idx % 200 + 1}",
        dst_port: 443,
        proto: "tcp",
        score: 50,
        reasons_json: "[]",
        total_bytes: 0,
        created_at: now,
        updated_at: now
      }
    end
    AnomalyHit.insert_all!(hits)

    elapsed = Benchmark.realtime { get "/search/anomalies" }
    expect(response).to have_http_status(:ok)
    expect(elapsed).to be < 2.0
  end
end
