# frozen_string_literal: true

require "rails_helper"

RSpec.describe Search::AnomaliesQuery do
  it "filters by code and ack" do
    device = Device.create!(ip: "10.0.0.2", name: "desk")
    AnomalyHit.create!(
      occurred_at: 1.hour.ago,
      device_id: device.id,
      dst_ip: "8.8.8.8",
      dst_port: 53,
      score: 70,
      reasons_json: [{ code: "RARE_PORT" }].to_json,
      acknowledged_at: nil
    )
    AnomalyHit.create!(
      occurred_at: 1.hour.ago,
      device_id: device.id,
      dst_ip: "1.1.1.1",
      dst_port: 53,
      score: 70,
      reasons_json: [{ code: "NEW_DST" }].to_json,
      acknowledged_at: Time.current
    )

    query = described_class.new(code: "RARE_PORT", ack: "0")

    expect(query.results.map(&:dst_ip)).to eq(["8.8.8.8"])
  end
end
