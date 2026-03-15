# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Netmon events API", type: :request do
  let(:headers) do
    {
      "Authorization" => "Bearer test-token"
    }
  end

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("NETMON_API_TOKEN", "").and_return("test-token")
  end

  it "ingests dns_response events through the batch API" do
    post "/api/v1/netmon/events/batch",
         params: {
           router_id: "router-1",
           events: [
             {
               type: "dns_response",
               ts: "2026-03-15T12:00:00Z",
               data: {
                 client_ip: "10.0.0.20",
                 qname: "api.github.com",
                 qtype: "A",
                 answers: [
                   { type: "A", data: "203.0.113.10" },
                   { type: "TXT", data: "ignored" }
                 ]
               }
             }
           ]
         },
         headers: headers

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq("accepted" => 1, "rejected" => 0)
    expect(NetmonEvent.count).to eq(1)
    expect(DnsEvent.count).to eq(1)
    expect(DnsEventAnswer.pluck(:answer_type, :answer_ip)).to eq([["A", "203.0.113.10"]])
  end

  it "tolerates malformed dns payloads without blocking flow ingestion" do
    allow(Netmon::HostEnricher).to receive(:apply)
    allow(Netmon::Anomaly::DeviceStats).to receive(:current).and_return(
      Netmon::Anomaly::DeviceStats::Result.new(
        uplink_bytes_last_10m: 0,
        new_dst_ips_last_10m: 0,
        unique_ports_last_10m: 0
      )
    )
    allow(Netmon::Anomaly::Scorer).to receive(:score_connection).and_return(score: 0, reasons: [])

    post "/api/v1/netmon/events/batch",
         params: {
           router_id: "router-1",
           events: [
             {
               type: "dns_response",
               ts: "2026-03-15T12:00:00Z",
               data: {
                 client_ip: "10.0.0.20",
                 qtype: "A",
                 answers: "not-an-array"
               }
             },
             {
               type: "flow",
               ts: "2026-03-15T12:00:10Z",
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
             }
           ]
         },
         headers: headers

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq("accepted" => 2, "rejected" => 0)
    expect(DnsEvent.count).to eq(0)
    expect(Connection.count).to eq(1)
  end
end
