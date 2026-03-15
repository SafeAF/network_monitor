# frozen_string_literal: true

require "rails_helper"

RSpec.describe Search::HostsQuery do
  it "filters by ip prefix" do
    RemoteHost.create!(ip: "10.0.0.1", first_seen_at: 1.hour.ago, last_seen_at: 1.minute.ago, tag: "cloud")
    RemoteHost.create!(ip: "192.168.1.5", first_seen_at: 2.hours.ago, last_seen_at: 2.minutes.ago, tag: "cdn")

    query = described_class.new(ip: "10.")

    expect(query.results.map(&:ip)).to eq(["10.0.0.1"])
  end

  it "filters by tag" do
    RemoteHost.create!(ip: "10.0.0.2", first_seen_at: 1.hour.ago, last_seen_at: 1.minute.ago, tag: "cloud")
    RemoteHost.create!(ip: "10.0.0.3", first_seen_at: 1.hour.ago, last_seen_at: 1.minute.ago, tag: "cdn")

    query = described_class.new(tag: "cdn")

    expect(query.results.map(&:tag)).to eq(["cdn"])
  end

  it "filters by associated domain substring" do
    matched_host = RemoteHost.create!(ip: "10.0.0.20", first_seen_at: 1.hour.ago, last_seen_at: 1.minute.ago, tag: "cloud")
    other_host = RemoteHost.create!(ip: "10.0.0.21", first_seen_at: 1.hour.ago, last_seen_at: 1.minute.ago, tag: "cloud")

    RemoteHostDomain.create!(
      remote_host: matched_host,
      domain: "api.github.com",
      first_seen_at: 30.minutes.ago,
      last_seen_at: 5.minutes.ago,
      seen_count: 3
    )
    RemoteHostDomain.create!(
      remote_host: other_host,
      domain: "cdn.cloudflare.net",
      first_seen_at: 30.minutes.ago,
      last_seen_at: 5.minutes.ago,
      seen_count: 2
    )

    query = described_class.new(domain: "github")

    expect(query.results.map(&:ip)).to eq(["10.0.0.20"])
  end

  it "clamps per to max" do
    RemoteHost.create!(ip: "10.0.0.4", first_seen_at: 1.hour.ago, last_seen_at: 1.minute.ago, tag: "cloud")
    query = described_class.new(per: 500)

    expect(query.per).to eq(200)
  end
end
