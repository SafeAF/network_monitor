# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Incidents pages", type: :request do
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

  it "renders incidents index with filters" do
    Incident.create!(
      fingerprint: "1|203.0.113.10|443|tcp|RARE_PORT",
      device_id: device.id,
      dst_ip: "203.0.113.10",
      dst_port: 443,
      proto: "tcp",
      codes_csv: "RARE_PORT",
      first_seen_at: Time.current - 10.minutes,
      last_seen_at: Time.current - 5.minutes,
      count: 1,
      max_score: 80
    )
    Incident.create!(
      fingerprint: "1|203.0.113.11|443|tcp|HIGH_EGRESS",
      device_id: device.id,
      dst_ip: "203.0.113.11",
      dst_port: 443,
      proto: "tcp",
      codes_csv: "HIGH_EGRESS",
      first_seen_at: Time.current - 2.days,
      last_seen_at: Time.current - 2.days,
      count: 1,
      max_score: 20
    )

    get "/incidents", params: { min_score: 50, code: "RARE", window: "1h" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("203.0.113.10")
    expect(response.body).not_to include("203.0.113.11")
  end

  it "acks an incident" do
    incident = Incident.create!(
      fingerprint: "1|203.0.113.10|443|tcp|RARE_PORT",
      device_id: device.id,
      dst_ip: "203.0.113.10",
      dst_port: 443,
      proto: "tcp",
      codes_csv: "RARE_PORT",
      first_seen_at: Time.current - 10.minutes,
      last_seen_at: Time.current - 5.minutes,
      count: 1,
      max_score: 80
    )

    post "/incidents/#{incident.id}/ack", params: { incident: { ack_notes: "OK" } }
    incident.reload

    expect(response).to have_http_status(:redirect)
    expect(incident.acknowledged_at).not_to be_nil
    expect(incident.ack_notes).to eq("OK")
  end
end
