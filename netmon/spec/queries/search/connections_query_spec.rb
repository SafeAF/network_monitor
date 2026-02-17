# frozen_string_literal: true

require "rails_helper"

RSpec.describe Search::ConnectionsQuery do
  it "filters by minimum total bytes" do
    Connection.create!(
      proto: "tcp",
      src_ip: "10.0.0.2",
      dst_ip: "1.1.1.1",
      dst_port: 443,
      first_seen_at: 1.hour.ago,
      last_seen_at: 1.minute.ago,
      uplink_bytes: 100,
      downlink_bytes: 100
    )
    Connection.create!(
      proto: "tcp",
      src_ip: "10.0.0.3",
      dst_ip: "2.2.2.2",
      dst_port: 443,
      first_seen_at: 1.hour.ago,
      last_seen_at: 1.minute.ago,
      uplink_bytes: 5000,
      downlink_bytes: 2000
    )

    query = described_class.new(min_total_bytes: 1000)
    results = query.results

    expect(results.map(&:dst_ip)).to eq(["2.2.2.2"])
  end

  it "sorts by total bytes" do
    Connection.create!(
      proto: "tcp",
      src_ip: "10.0.0.2",
      dst_ip: "3.3.3.3",
      dst_port: 80,
      first_seen_at: 1.hour.ago,
      last_seen_at: 1.minute.ago,
      uplink_bytes: 100,
      downlink_bytes: 100
    )
    Connection.create!(
      proto: "tcp",
      src_ip: "10.0.0.2",
      dst_ip: "4.4.4.4",
      dst_port: 80,
      first_seen_at: 1.hour.ago,
      last_seen_at: 1.minute.ago,
      uplink_bytes: 2000,
      downlink_bytes: 2000
    )

    query = described_class.new(sort: "total_bytes", dir: "desc")

    expect(query.results.first.dst_ip).to eq("4.4.4.4")
  end
end
