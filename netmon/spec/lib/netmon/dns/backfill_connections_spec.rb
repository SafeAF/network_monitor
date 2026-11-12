# frozen_string_literal: true

require "rails_helper"

RSpec.describe Netmon::Dns::BackfillConnections do
  let(:now) { Time.current }
  let(:host) { RemoteHost.create!(ip: "203.0.113.8", first_seen_at: now, last_seen_at: now) }
  let(:event) do
    row = DnsEvent.create!(router_id: "router-1", observed_at: now, client_ip: "10.0.0.20",
      qname: "client.example", qtype: "A", answers_json: "[]", dedupe_key: "backfill")
    DnsEventAnswer.create!(dns_event: row, answer_ip: host.ip, answer_type: "A")
    row
  end

  def connection(port, seen_at:, client: "10.0.0.20")
    Connection.create!(proto: "tcp", src_ip: client, src_port: port, dst_ip: host.ip,
      dst_port: 443, first_seen_at: seen_at, last_seen_at: seen_at)
  end

  it "only labels same-client flows at or after the DNS observation within its window" do
    matching = connection(1, seen_at: now + 1.second)
    before_dns = connection(2, seen_at: now - 1.second)
    expired = connection(3, seen_at: now + 11.minutes)
    other_client = connection(4, seen_at: now + 1.second, client: "10.0.0.21")
    expect(described_class.call(dns_event: event, strict: true)).to eq(1)
    expect(matching.reload.last_domain).to eq("client.example")
    expect([before_dns, expired, other_client].map { |row| row.reload.last_domain }).to eq([nil, nil, nil])
    expect(RemoteHostDomain.count).to eq(1)
  end

  it "does not let a foreign router, PTR lookup or failed response label flows" do
    row = connection(1, seen_at: now + 1.second)
    event.update!(router_id: "router-2")
    expect { described_class.call(dns_event: event, strict: true) }.to raise_error(Netmon::RouterPolicy::Mismatch)
    event.update!(router_id: "router-1", qtype: "PTR")
    expect(described_class.call(dns_event: event, strict: true)).to eq(0)
    event.update!(qtype: "A", rcode: "NXDOMAIN")
    expect(described_class.call(dns_event: event, strict: true)).to eq(0)
    expect(row.reload.last_domain).to be_nil
    expect(RemoteHostDomain.count).to eq(0)
  end
end
