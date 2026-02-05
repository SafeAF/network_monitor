# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Connections JSON", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    Time.zone = "UTC"
    travel_to(Time.zone.parse("2026-02-03 12:00:00")) { example.run }
  end

  it "returns connections with seen_before" do
    RemoteHost.create!(ip: "203.0.113.10", first_seen_at: Time.current - 120, last_seen_at: Time.current)
    Connection.create!(
      proto: "tcp",
      src_ip: "10.0.0.24",
      src_port: 12345,
      dst_ip: "203.0.113.10",
      dst_port: 443,
      state: "ESTABLISHED",
      flags: "ASSURED",
      uplink_packets: 1,
      uplink_bytes: 100,
      downlink_packets: 2,
      downlink_bytes: 200,
      first_seen_at: Time.current - 120,
      last_seen_at: Time.current
    )

    get "/connections.json"

    expect(response).to have_http_status(:ok)
    payload = JSON.parse(response.body)
    expect(payload.length).to eq(1)
    expect(payload[0]["seen_before"]).to eq(true)
    expect(payload[0]["total_bytes"]).to eq(300)
  end

  it "marks recent hosts as not seen_before" do
    RemoteHost.create!(ip: "198.51.100.7", first_seen_at: Time.current - 30, last_seen_at: Time.current)
    Connection.create!(
      proto: "tcp",
      src_ip: "10.0.0.24",
      src_port: 2222,
      dst_ip: "198.51.100.7",
      dst_port: 443,
      uplink_packets: 1,
      uplink_bytes: 10,
      downlink_packets: 1,
      downlink_bytes: 20,
      first_seen_at: Time.current - 30,
      last_seen_at: Time.current
    )

    get "/connections.json"

    payload = JSON.parse(response.body)
    expect(payload[0]["seen_before"]).to eq(false)
  end
end
