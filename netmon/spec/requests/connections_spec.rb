# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Connections JSON", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    Time.zone = "UTC"
    travel_to(Time.zone.parse("2026-02-03 12:00:00")) { example.run }
  end

  it "returns connections with seen_before" do
    remote_attrs = {
      ip: "203.0.113.10",
      first_seen_at: Time.current - 120,
      last_seen_at: Time.current,
      rdns_name: "cache.example.net",
      whois_name: "Example Org"
    }
    if RemoteHost.column_names.include?("whois_raw_line")
      remote_attrs[:whois_raw_line] = "OrgName: Example Org"
    end
    RemoteHost.create!(remote_attrs)
    Device.create!(
      ip: "10.0.0.24",
      name: "Desktop",
      first_seen_at: Time.current - 120,
      last_seen_at: Time.current
    )
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
    expect(payload[0]["rdns_name"]).to eq("cache.example.net")
    expect(payload[0]["whois_name"]).to eq("Example Org")
    if RemoteHost.column_names.include?("whois_raw_line")
      expect(payload[0]["whois_raw_line"]).to eq("OrgName: Example Org")
    end
    expect(payload[0]["device_name"]).to eq("Desktop")
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

  it "filters out TIME_WAIT when requested" do
    RemoteHost.create!(ip: "203.0.113.50", first_seen_at: Time.current - 120, last_seen_at: Time.current)
    Connection.create!(
      proto: "tcp",
      src_ip: "10.0.0.24",
      src_port: 2222,
      dst_ip: "203.0.113.50",
      dst_port: 443,
      state: "TIME_WAIT",
      uplink_packets: 1,
      uplink_bytes: 10,
      downlink_packets: 1,
      downlink_bytes: 20,
      first_seen_at: Time.current - 30,
      last_seen_at: Time.current
    )
    Connection.create!(
      proto: "tcp",
      src_ip: "10.0.0.24",
      src_port: 3333,
      dst_ip: "203.0.113.51",
      dst_port: 443,
      state: "ESTABLISHED",
      uplink_packets: 1,
      uplink_bytes: 10,
      downlink_packets: 1,
      downlink_bytes: 20,
      first_seen_at: Time.current - 30,
      last_seen_at: Time.current
    )

    get "/connections.json", params: { hide_time_wait: "true" }

    payload = JSON.parse(response.body)
    expect(payload.length).to eq(1)
    expect(payload[0]["state"]).to eq("ESTABLISHED")
  end

  it "filters to only new hosts" do
    RemoteHost.create!(ip: "198.51.100.7", first_seen_at: Time.current - 30, last_seen_at: Time.current)
    RemoteHost.create!(ip: "203.0.113.9", first_seen_at: Time.current - 300, last_seen_at: Time.current)

    Connection.create!(
      proto: "tcp",
      src_ip: "10.0.0.24",
      src_port: 1111,
      dst_ip: "198.51.100.7",
      dst_port: 443,
      uplink_packets: 1,
      uplink_bytes: 10,
      downlink_packets: 1,
      downlink_bytes: 20,
      first_seen_at: Time.current - 30,
      last_seen_at: Time.current
    )
    Connection.create!(
      proto: "tcp",
      src_ip: "10.0.0.24",
      src_port: 2222,
      dst_ip: "203.0.113.9",
      dst_port: 443,
      uplink_packets: 1,
      uplink_bytes: 10,
      downlink_packets: 1,
      downlink_bytes: 20,
      first_seen_at: Time.current - 300,
      last_seen_at: Time.current
    )

    get "/connections.json", params: { only_new: "true" }

    payload = JSON.parse(response.body)
    expect(payload.length).to eq(1)
    expect(payload[0]["dst_ip"]).to eq("198.51.100.7")
    expect(payload[0]["is_new"]).to eq(true)
  end
end
