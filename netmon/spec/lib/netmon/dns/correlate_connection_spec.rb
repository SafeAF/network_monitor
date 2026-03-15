# frozen_string_literal: true

require "rails_helper"

RSpec.describe Netmon::Dns::CorrelateConnection do
  it "picks the most recent matching dns_event within the correlation window" do
    now = Time.zone.parse("2026-03-15 12:00:00 UTC")
    connection = Connection.new(src_ip: "10.0.0.20", dst_ip: "203.0.113.10")

    old_event = DnsEvent.create!(
      router_id: "router-1",
      observed_at: now - 9.minutes,
      client_ip: "10.0.0.20",
      qname: "old.example.com",
      qtype: "A",
      answers_json: [{ type: "A", data: "203.0.113.10" }].to_json,
      dedupe_key: "old-match"
    )
    DnsEventAnswer.create!(dns_event: old_event, answer_ip: "203.0.113.10", answer_type: "A")

    recent_event = DnsEvent.create!(
      router_id: "router-1",
      observed_at: now - 2.minutes,
      client_ip: "10.0.0.20",
      qname: "api.github.com",
      qtype: "A",
      answers_json: [{ type: "A", data: "203.0.113.10" }].to_json,
      dedupe_key: "recent-match"
    )
    DnsEventAnswer.create!(dns_event: recent_event, answer_ip: "203.0.113.10", answer_type: "A")

    result = described_class.call(connection: connection, now: now)

    expect(result).to eq(
      domain: "api.github.com",
      observed_at: recent_event.observed_at
    )
  end
end
