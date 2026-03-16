# frozen_string_literal: true

require "rails_helper"

RSpec.describe Netmon::Dns::IngestEvent do
  let(:router_id) { "router-1" }
  let(:ts) { Time.zone.parse("2026-03-15 12:00:00 UTC") }

  it "ingests dns_response payloads and extracts only A and AAAA answers" do
    raw_answers = [
      { type: "A", data: "203.0.113.10" },
      { type: "AAAA", data: "2001:db8::10" },
      { type: "CNAME", data: "edge.example.net" },
      { type: "A", data: "not-an-ip" }
    ]

    dns_event = described_class.call(
      router_id: router_id,
      ts: ts,
      data: {
        client_ip: "10.0.0.20",
        qname: "Api.GitHub.com",
        qtype: "a",
        answers: raw_answers
      }
    )

    expect(dns_event).not_to be_nil
    expect(dns_event.qtype).to eq("A")
    expect(dns_event.answers).to eq(raw_answers.as_json)
    expect(dns_event.dns_event_answers.order(:answer_type, :answer_ip).pluck(:answer_type, :answer_ip)).to eq([
      ["A", "203.0.113.10"],
      ["AAAA", "2001:db8::10"]
    ])
  end

  it "is idempotent for the same normalized payload and timestamp" do
    payload = {
      client_ip: "10.0.0.20",
      qname: "api.github.com",
      qtype: "A",
      answers: [{ type: "A", data: "203.0.113.10" }]
    }

    first = described_class.call(router_id: router_id, ts: ts, data: payload)
    second = described_class.call(router_id: router_id, ts: ts, data: payload.deep_dup)

    expect(first.id).to eq(second.id)
    expect(DnsEvent.count).to eq(1)
    expect(DnsEventAnswer.count).to eq(1)
  end

  it "logs and skips malformed payloads" do
    allow(Rails.logger).to receive(:warn)

    result = described_class.call(
      router_id: router_id,
      ts: ts,
      data: {
        client_ip: "10.0.0.20",
        qtype: "A",
        answers: "invalid"
      }
    )

    expect(result).to be_nil
    expect(DnsEvent.count).to eq(0)
    expect(DnsEventAnswer.count).to eq(0)
    expect(Rails.logger).to have_received(:warn).with(/dns_ingest/)
  end

  it "backfills a recent matching connection when dns arrives after flow ingest" do
    remote_host = RemoteHost.create!(
      ip: "198.252.206.17",
      first_seen_at: ts - 5.minutes,
      last_seen_at: ts + 20.seconds
    )
    Connection.create!(
      proto: "udp",
      src_ip: "10.0.0.20",
      src_port: 57_000,
      dst_ip: remote_host.ip,
      dst_port: 443,
      first_seen_at: ts + 20.seconds,
      last_seen_at: ts + 20.seconds
    )

    dns_event = described_class.call(
      router_id: router_id,
      ts: ts,
      data: {
        client_ip: "10.0.0.20",
        qname: "stackoverflow.com",
        qtype: "A",
        answers: [{ type: "A", data: remote_host.ip }]
      }
    )

    connection = Connection.find_by!(src_ip: "10.0.0.20", dst_ip: remote_host.ip)
    remote_host_domain = RemoteHostDomain.find_by!(remote_host_id: remote_host.id, domain: "stackoverflow.com")

    expect(dns_event).not_to be_nil
    expect(connection.last_domain).to eq("stackoverflow.com")
    expect(connection.last_domain_observed_at).to eq(ts)
    expect(remote_host_domain.last_device_ip).to eq("10.0.0.20")
  end
end
