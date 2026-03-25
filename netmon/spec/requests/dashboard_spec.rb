# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  include ActiveSupport::Testing::TimeHelpers

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
    expect(response.body).to include('name="hide_states[]"')
    expect(response.body).to include('value="DESTROY"')
    expect(response.body).to include('value="SYN_SENT"')
    expect(response.body).to include("Active Connections")
  end
end
