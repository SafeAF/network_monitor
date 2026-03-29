# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  before do
    Rails.cache.clear
  end

  around do |example|
    Time.zone = "UTC"
    travel_to(Time.zone.parse("2026-03-20 12:00:00")) { example.run }
  end

  it "renders with only_new enabled and includes selective hide-state controls" do
    RemoteHost.create!(ip: "198.51.100.7", first_seen_at: Time.current - 30.seconds, last_seen_at: Time.current)
    Connection.create!(
      proto: "udp",
      src_ip: "10.0.0.24",
      src_port: 55_000,
      dst_ip: "198.51.100.7",
      dst_port: 53,
      state: "NEW",
      uplink_packets: 0,
      uplink_bytes: 0,
      downlink_packets: 0,
      downlink_bytes: 0,
      first_seen_at: Time.current - 30.seconds,
      last_seen_at: Time.current
    )

    get "/", params: { only_new: "true" }

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("application.tailwind")
    expect(response.body).to include('name="hide_states[]"')
    expect(response.body).to include('value="DESTROY"')
    expect(response.body).to include('value="SYN_SENT"')
    expect(response.body).to include("Active Connections")
  end

  it "serves cached top panels JSON" do
    cache_store = ActiveSupport::Cache::MemoryStore.new
    allow(Rails).to receive(:cache).and_return(cache_store)

    remote_host = RemoteHost.create!(ip: "198.51.100.7", first_seen_at: Time.current - 30.seconds, last_seen_at: Time.current)
    RemoteHostMinute.create!(
      remote_host: remote_host,
      bucket_ts: Time.current.change(sec: 0),
      uplink_bytes: 512,
      downlink_bytes: 1024,
      uplink_packets: 4,
      downlink_packets: 8,
      conn_count: 1
    )

    get "/dashboard/top_panels.json"
    body = JSON.parse(response.body)

    expect(response).to have_http_status(:ok)
    expect(body.fetch("top_remote_hosts")).to include(
      a_hash_including("ip" => "198.51.100.7", "total_bytes" => 1536)
    )

    remote_host.update!(ip: "203.0.113.9")

    get "/dashboard/top_panels.json"
    cached_body = JSON.parse(response.body)

    expect(cached_body.fetch("top_remote_hosts")).to include(
      a_hash_including("ip" => "198.51.100.7", "total_bytes" => 1536)
    )
  end
end
