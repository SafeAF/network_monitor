# frozen_string_literal: true

require "rails_helper"

RSpec.describe Netmon::Dns::Prune do
  it "deletes raw DNS rows older than 30 days and keeps aggregate domains" do
    now = Time.zone.parse("2026-03-15 12:00:00")
    remote_host = RemoteHost.create!(
      ip: "203.0.113.44",
      first_seen_at: now - 40.days,
      last_seen_at: now - 1.minute
    )
    aggregate = RemoteHostDomain.create!(
      remote_host: remote_host,
      domain: "api.github.com",
      first_seen_at: now - 35.days,
      last_seen_at: now - 1.day,
      seen_count: 7,
      last_device_ip: "10.0.0.20"
    )

    old_event = DnsEvent.create!(
      router_id: "router-1",
      observed_at: now - 31.days,
      client_ip: "10.0.0.20",
      qname: "api.github.com",
      qtype: "A",
      answers_json: ["203.0.113.44"].to_json,
      dedupe_key: "old-key"
    )
    old_answer = DnsEventAnswer.create!(
      dns_event: old_event,
      answer_ip: "203.0.113.44",
      answer_type: "A"
    )

    fresh_event = DnsEvent.create!(
      router_id: "router-1",
      observed_at: now - 5.days,
      client_ip: "10.0.0.20",
      qname: "cdn.cloudflare.net",
      qtype: "A",
      answers_json: ["198.51.100.10"].to_json,
      dedupe_key: "fresh-key"
    )
    fresh_answer = DnsEventAnswer.create!(
      dns_event: fresh_event,
      answer_ip: "198.51.100.10",
      answer_type: "A"
    )

    result = described_class.call(now: now)

    expect(result.dns_events_deleted).to eq(1)
    expect(result.dns_event_answers_deleted).to eq(1)
    expect(DnsEvent.exists?(old_event.id)).to eq(false)
    expect(DnsEventAnswer.exists?(old_answer.id)).to eq(false)
    expect(DnsEvent.exists?(fresh_event.id)).to eq(true)
    expect(DnsEventAnswer.exists?(fresh_answer.id)).to eq(true)
    expect(RemoteHostDomain.exists?(aggregate.id)).to eq(true)
  end
end
