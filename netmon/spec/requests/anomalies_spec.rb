# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Anomalies page", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    Time.zone = "UTC"
    travel_to(Time.zone.parse("2026-02-06 12:00:00")) { example.run }
  end

  it "renders and filters by min_score and dst_ip" do
    device = Device.create!(
      ip: "10.0.0.24",
      name: "Desktop",
      first_seen_at: Time.current - 1.day,
      last_seen_at: Time.current
    )

    AnomalyHit.create!(
      occurred_at: Time.current - 10.minutes,
      device_id: device.id,
      dst_ip: "203.0.113.10",
      dst_port: 443,
      proto: "tcp",
      score: 80,
      reasons_json: [{ code: "NEW_DST", weight: 30 }].to_json
    )
    AnomalyHit.create!(
      occurred_at: Time.current - 10.minutes,
      device_id: device.id,
      dst_ip: "203.0.113.11",
      dst_port: 443,
      proto: "tcp",
      score: 20,
      reasons_json: [{ code: "NO_RDNS", weight: 10 }].to_json
    )

    get "/anomalies", params: { min_score: 50, dst_ip: "203.0.113.10" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("203.0.113.10")
    expect(response.body).not_to include("203.0.113.11")
  end
end
