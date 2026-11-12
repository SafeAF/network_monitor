# frozen_string_literal: true

require "rails_helper"

RSpec.describe Netmon::AgentIngest do
  before do
    allow(Netmon::HostEnricher).to receive(:apply)
    allow(Netmon::Anomaly::DeviceStats).to receive(:current).and_return(
      Netmon::Anomaly::DeviceStats::Result.new(
        uplink_bytes_last_10m: 0,
        new_dst_ips_last_10m: 0,
        unique_ports_last_10m: 0
      )
    )
    allow(Netmon::Anomaly::Scorer).to receive(:score_connection).and_return(score: 0, reasons: [])
  end

  it "updates remote_host_domains only when a matching connection correlation exists" do
    now = Time.zone.parse("2026-03-15 12:00:00 UTC")
    dns_event = DnsEvent.create!(
      router_id: "router-1",
      observed_at: now - 2.minutes,
      client_ip: "10.0.0.20",
      qname: "api.github.com",
      qtype: "A",
      answers_json: [{ type: "A", data: "203.0.113.10" }].to_json,
      dedupe_key: "match-key"
    )
    DnsEventAnswer.create!(dns_event: dns_event, answer_ip: "203.0.113.10", answer_type: "A")

    described_class.ingest_event!(
      event_type: "flow",
      router_id: "router-1",
      ts: now,
      data: {
        src_ip: "10.0.0.20",
        dst_ip: "203.0.113.10",
        src_port: 55_000,
        dst_port: 443,
        l4proto: 6,
        bytes_orig: 100,
        bytes_reply: 200,
        packets_orig: 1,
        packets_reply: 2
      }
    )

    remote_host = RemoteHost.find_by!(ip: "203.0.113.10")
    connection = Connection.find_by!(src_ip: "10.0.0.20", dst_ip: "203.0.113.10")
    linked_domain = RemoteHostDomain.find_by(remote_host_id: remote_host.id)

    expect(connection.last_domain).to eq("api.github.com")
    expect(connection.last_domain_observed_at).to eq(dns_event.observed_at)
    expect(linked_domain.domain).to eq("api.github.com")
    expect(linked_domain.last_device_ip).to eq("10.0.0.20")
    expect(linked_domain.seen_count).to eq(1)
  end

  it "does not update remote_host_domains when there is no matching dns correlation" do
    now = Time.zone.parse("2026-03-15 12:00:00 UTC")
    dns_event = DnsEvent.create!(
      router_id: "router-1",
      observed_at: now - 2.minutes,
      client_ip: "10.0.0.20",
      qname: "api.github.com",
      qtype: "A",
      answers_json: [{ type: "A", data: "203.0.113.99" }].to_json,
      dedupe_key: "non-match-key"
    )
    DnsEventAnswer.create!(dns_event: dns_event, answer_ip: "203.0.113.99", answer_type: "A")

    described_class.ingest_event!(
      event_type: "flow",
      router_id: "router-1",
      ts: now,
      data: {
        src_ip: "10.0.0.20",
        dst_ip: "203.0.113.10",
        src_port: 55_000,
        dst_port: 443,
        l4proto: 6,
        bytes_orig: 100,
        bytes_reply: 200,
        packets_orig: 1,
        packets_reply: 2
      }
    )

    connection = Connection.find_by!(src_ip: "10.0.0.20", dst_ip: "203.0.113.10")

    expect(connection.last_domain).to be_nil
    expect(RemoteHostDomain.count).to eq(0)
  end

  it "does not attribute a flow to a PTR lookup from another client" do
    now = Time.zone.parse("2026-03-15 12:00:00 UTC")
    dns_event = DnsEvent.create!(
      router_id: "router-1",
      observed_at: now - 30.seconds,
      client_ip: "10.0.0.10",
      qname: "stackoverflow.com",
      qtype: "PTR",
      answers_json: [{ type: "A", data: "198.252.206.17" }].to_json,
      dedupe_key: "ptr-flow-match"
    )
    DnsEventAnswer.create!(dns_event: dns_event, answer_ip: "198.252.206.17", answer_type: "A")

    described_class.ingest_event!(
      event_type: "flow",
      router_id: "router-1",
      ts: now,
      data: {
        src_ip: "10.0.0.20",
        dst_ip: "198.252.206.17",
        src_port: 55_000,
        dst_port: 443,
        l4proto: 6,
        bytes_orig: 100,
        bytes_reply: 200,
        packets_orig: 1,
        packets_reply: 2
      }
    )

    remote_host = RemoteHost.find_by!(ip: "198.252.206.17")
    connection = Connection.find_by!(src_ip: "10.0.0.20", dst_ip: "198.252.206.17")
    linked_domain = RemoteHostDomain.find_by(remote_host_id: remote_host.id)

    expect(connection.last_domain).to be_nil
    expect(connection.last_domain_observed_at).to be_nil
    expect(linked_domain).to be_nil
  end

  it "clears a cached domain after its DNS correlation window expires" do
    now = Time.current
    connection = Connection.create!(proto: "tcp", src_ip: "10.0.0.20", src_port: 55000,
      dst_ip: "203.0.113.10", dst_port: 443, first_seen_at: now - 1.hour, last_seen_at: now - 1.minute,
      last_domain: "expired.example", last_domain_observed_at: now - 11.minutes)

    described_class.ingest_event!(event_type: "flow", router_id: "router-1", ts: now,
      data: { src_ip: connection.src_ip, dst_ip: connection.dst_ip, src_port: 55000, dst_port: 443,
        l4proto: 6, bytes_orig: 100, bytes_reply: 100 })

    expect(connection.reload.last_domain).to be_nil
    expect(connection.last_domain_observed_at).to be_nil
  end

  it "rescores an existing connection on a destroy update" do
    now = Time.zone.parse("2026-03-15 12:00:00 UTC")
    allow(Netmon::Anomaly::Scorer).to receive(:score_connection).and_return(score: 7, reasons: [{ code: "NEW_DST" }])

    described_class.ingest_event!(
      event_type: "flow",
      router_id: "router-1",
      ts: now,
      data: {
        src_ip: "10.0.0.20",
        dst_ip: "203.0.113.10",
        src_port: 55_000,
        dst_port: 443,
        l4proto: 6,
        state: "NEW",
        bytes_orig: 100,
        bytes_reply: 200,
        packets_orig: 1,
        packets_reply: 2
      }
    )

    described_class.ingest_event!(
      event_type: "flow",
      router_id: "router-1",
      ts: now + 5.seconds,
      data: {
        src_ip: "10.0.0.20",
        dst_ip: "203.0.113.10",
        src_port: 55_000,
        dst_port: 443,
        l4proto: 6,
        state: "DESTROY",
        bytes_orig: 150,
        bytes_reply: 260,
        packets_orig: 2,
        packets_reply: 3
      }
    )

    connection = Connection.find_by!(src_ip: "10.0.0.20", dst_ip: "203.0.113.10", dst_port: 443)

    expect(Netmon::Anomaly::Scorer).to have_received(:score_connection).twice
    expect(connection.state).to eq("DESTROY")
    expect(connection.anomaly_score).to eq(7)
  end
end
