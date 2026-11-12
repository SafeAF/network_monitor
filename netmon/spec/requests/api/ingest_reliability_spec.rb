# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ingest reliability", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    travel_to(Time.zone.parse("2026-11-12T12:00:00Z")) { example.run }
  end

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("NETMON_API_TOKEN", "").and_return("test-token")
    allow(Netmon::HostEnricher).to receive(:apply).and_raise("enrichment must not run during ingestion")
    allow(Netmon::Anomaly::DeviceStats).to receive(:current).and_return(
      Netmon::Anomaly::DeviceStats::Result.new(uplink_bytes_last_10m: 0, new_dst_ips_last_10m: 0, unique_ports_last_10m: 0)
    )
    allow(Netmon::Anomaly::Scorer).to receive(:score_connection).and_return(score: 0, reasons: [])
  end

  def flow(id = "event-1", ts: Time.current.iso8601)
    { id: id, type: "flow", ts: ts, data: { src_ip: "10.0.0.20", dst_ip: "203.0.113.8",
      src_port: 50000, dst_port: 443, l4proto: 6, bytes_orig: 100, bytes_reply: 200, packets_orig: 1, packets_reply: 2 } }
  end

  def send_batch(events, router_id: "router-1")
    post "/api/v1/netmon/events/batch", params: { router_id: router_id, events: events },
      headers: { "Authorization" => "Bearer test-token", "X-Netmon-Protocol-Version" => "1" }, as: :json
    JSON.parse(response.body)
  end

  it "acknowledges retries as duplicates without repeating normalized writes" do
    payload = flow
    expect(send_batch([payload])["results"]).to include(a_hash_including("status" => "accepted"))
    counts = [NetmonEvent.count, DeviceMinute.sum(:conn_count), RemoteHostMinute.sum(:conn_count), RemoteHostPort.sum(:seen_count)]
    expect(send_batch([payload])["results"]).to include(a_hash_including("status" => "duplicate"))
    expect([NetmonEvent.count, DeviceMinute.sum(:conn_count), RemoteHostMinute.sum(:conn_count), RemoteHostPort.sum(:seen_count)]).to eq(counts)
    expect(Netmon::HostEnricher).not_to have_received(:apply)
  end

  it "rejects identity reuse with different content" do
    payload = flow
    send_batch([payload])
    payload[:data][:bytes_orig] = 500
    expect(send_batch([payload])["results"]).to include(a_hash_including("status" => "rejected", "code" => "id_conflict"))
    expect(NetmonEvent.count).to eq(1)
    expect(Connection.first.uplink_bytes).to eq(100)
  end

  it "rolls back raw receipts, devices, and hosts on a mid-event exception" do
    allow(Netmon::Anomaly::Scorer).to receive(:score_connection).and_raise("simulated failure")
    expect(send_batch([flow])).to include("accepted" => 0, "retryable" => 1)
    expect([NetmonEvent.count, Device.count, RemoteHost.count, Connection.count, DeviceMinute.count]).to eq([0, 0, 0, 0, 0])
    allow(Netmon::Anomaly::Scorer).to receive(:score_connection).and_return(score: 0, reasons: [])
    expect(send_batch([flow])["accepted"]).to eq(1)
  end

  it "does not acknowledge a transaction explicitly rolled back by a processor" do
    allow(Netmon::AgentIngest).to receive(:ingest_event!).and_raise(ActiveRecord::Rollback)
    expect(send_batch([flow])["retryable"]).to eq(1)
    expect(NetmonEvent.count).to eq(0)
  end

  it "rolls back DNS parents and raw receipts when answer persistence fails" do
    dns = { id: "dns-1", type: "dns_response", ts: Time.current.iso8601,
      data: { client_ip: "10.0.0.20", qname: "example.com", qtype: "A", answers: [{ type: "A", data: "203.0.113.8" }] } }
    allow(DnsEventAnswer).to receive(:create!).and_raise("simulated persistence failure")
    expect(send_batch([dns])["retryable"]).to eq(1)
    expect([NetmonEvent.count, DnsEvent.count, DnsEventAnswer.count]).to eq([0, 0, 0])
  end

  it "returns a result for every event in a mixed batch" do
    result = send_batch([nil, { type: "unsupported", data: {} }, flow])
    expect(result).to include("protocol_version" => 1, "accepted" => 1, "rejected" => 2, "retryable" => 0)
    expect(result["results"].map { |item| item["index"] }).to eq([0, 1, 2])
    expect(NetmonEvent.count).to eq(1)
  end

  it "rejects invalid envelopes without an unhandled exception" do
    expect(send_batch({})).to include("error" => "invalid_batch", "retryable" => false)
    expect(response).to have_http_status(:bad_request)
    expect(NetmonEvent.count).to eq(0)
  end

  it "derives stable identities for older agents without an id field" do
    payload = flow.except(:id)
    send_batch([payload])
    expect(send_batch([payload])["results"]).to include(a_hash_including("status" => "duplicate"))
    expect(NetmonEvent.count).to eq(1)
  end

  it "binds this installation to one router before normalizing any traffic" do
    heartbeat = { id: "same-id", type: "heartbeat", ts: Time.current.iso8601, data: {} }
    expect(send_batch([heartbeat], router_id: "router-1")["accepted"]).to eq(1)
    expect(IngestSource.find(1).router_id).to eq("router-1")
    expect(send_batch([heartbeat], router_id: "router-2")["code"]).to eq("router_mismatch")
    expect(response).to have_http_status(:bad_request)
    expect(NetmonEvent.count).to eq(1)
  end

  it "retains incoming batches when router configuration is missing or conflicts with the database" do
    send_batch([flow])
    allow(ENV).to receive(:fetch).with("NETMON_ROUTER_ID", "").and_return("")
    expect(send_batch([flow("missing-config")])).to include("code" => "router_not_configured", "retryable" => true)
    expect(response).to have_http_status(:service_unavailable)
    allow(ENV).to receive(:fetch).with("NETMON_ROUTER_ID", "").and_return("router-2")
    expect(send_batch([flow("conflicting-config")], router_id: "router-2")).to include("code" => "router_binding_conflict", "retryable" => true)
    expect(response).to have_http_status(:service_unavailable)
    expect(NetmonEvent.count).to eq(1)
    expect(IngestSource.find(1).router_id).to eq("router-1")
  end

  it "does not claim a router for invalid or rolled back events" do
    send_batch([{ type: "unsupported", data: {} }])
    expect(IngestSource.count).to eq(0)
    allow(Netmon::Anomaly::Scorer).to receive(:score_connection).and_raise("simulated failure")
    expect(send_batch([flow])["retryable"]).to eq(1)
    expect(IngestSource.count).to eq(0)
    expect(NetmonEvent.count).to eq(0)
  end

  it "keeps newer normalized flow counters when older spool events arrive" do
    send_batch([flow])
    old = flow("older-event", ts: (Time.current - 5.seconds).iso8601)
    old[:data][:bytes_orig] = 50
    expect(send_batch([old])["accepted"]).to eq(1)
    expect(Connection.first.uplink_bytes).to eq(100)
    expect(DeviceMinute.sum(:conn_count)).to eq(1)
    expect(NetmonEvent.count).to eq(2)
  end

  it "does not regress device and host observation times for a different older flow" do
    send_batch([flow])
    old = flow("older-connection", ts: (Time.current - 5.seconds).iso8601)
    old[:data][:src_port] = 50001
    expect(send_batch([old])["accepted"]).to eq(1)
    expect(Device.first.last_seen_at).to eq(Time.current)
    expect(RemoteHost.first.last_seen_at).to eq(Time.current)
    expect(RemoteHostPort.first.last_seen_at).to eq(Time.current)
  end

  it "rejects oversized raw bodies before processing events" do
    post "/api/v1/netmon/events/batch", params: "x" * (Netmon::RequestBodyLimit::MAX_BYTES + 1),
      headers: { "Authorization" => "Bearer test-token", "Content-Type" => "application/json" }
    expect(response).to have_http_status(413)
    expect(NetmonEvent.count).to eq(0)
  end

  it "makes partial failures non-2xx for legacy agents that ignore acknowledgement bodies" do
    allow(Netmon::Anomaly::Scorer).to receive(:score_connection).and_raise("transient processing failure")
    post "/api/v1/netmon/events/batch", params: { router_id: "router-1", events: [flow] },
      headers: { "Authorization" => "Bearer test-token" }, as: :json
    expect(response).to have_http_status(:service_unavailable)
    expect(JSON.parse(response.body)["retryable"]).to eq(1)
  end
end
