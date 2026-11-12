# frozen_string_literal: true

require "rails_helper"

RSpec.describe HostEnrichmentJob do
  it "retries score dispatch after metadata was already saved" do
    now = Time.current
    host = RemoteHost.create!(ip: "203.0.113.8", first_seen_at: now, last_seen_at: now)
    allow(Netmon::HostEnricher).to receive(:due?).and_return(true, false)
    allow(Netmon::HostEnricher).to receive(:apply) { |row| row.whois_asn = "AS64512" }
    allow(HostScoreRefreshJob).to receive(:perform_later).and_raise("queue unavailable")

    expect { described_class.new.perform(host.id) }.to raise_error("queue unavailable")
    expect(host.reload.whois_asn).to eq("AS64512")
    allow(HostScoreRefreshJob).to receive(:perform_later)
    described_class.new.perform(host.id)

    expect(Netmon::HostEnricher).to have_received(:apply).once
    expect(HostScoreRefreshJob).to have_received(:perform_later).with(host.id).twice
  end
end
