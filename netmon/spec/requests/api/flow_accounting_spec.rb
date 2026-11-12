# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Agent flow lifetime accounting", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    previous = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    travel_to(Time.zone.parse("2026-11-12T12:00:00Z")) { example.run }
  ensure
    ActiveJob::Base.queue_adapter = previous
  end

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("NETMON_API_TOKEN", "").and_return("test-token")
    allow(Netmon::Anomaly::Scorer).to receive(:score_connection).and_return(score: 0, reasons: [])
  end

  def ingest(id:, at:, lifecycle:, bytes:, flow_id: nil, port: 50000)
    data = { src_ip: "10.0.0.20", dst_ip: "203.0.113.8", src_port: port, dst_port: 443,
      l4proto: 6, event: "Event#{lifecycle}", state: "ESTABLISHED", bytes_orig: bytes,
      bytes_reply: bytes / 2, packets_orig: bytes / 10, packets_reply: bytes / 20 }
    data[:flow_id] = flow_id if flow_id
    post "/api/v1/netmon/events/batch", params: { router_id: "router-1", events: [
      { id: id, type: "flow", ts: at.iso8601(9), data: data }
    ] }, as: :json, headers: { "Authorization" => "Bearer test-token", "X-Netmon-Protocol-Version" => "1" }
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body)
  end

  it "counts a lifetime once and credits all bytes across NEW and DESTROY" do
    now = Time.current
    expect(ingest(id: "new", at: now, lifecycle: "New", bytes: 100)["accepted"]).to eq(1)
    expect(ingest(id: "end", at: now + 65.seconds, lifecycle: "Destroy", bytes: 1000)["accepted"]).to eq(1)
    expect([DeviceMinute.sum(:conn_count), RemoteHostMinute.sum(:conn_count), RemoteHostPort.sum(:seen_count)]).to eq([1, 1, 1])
    expect([DeviceMinute.sum(:uplink_bytes), RemoteHostMinute.sum(:downlink_bytes)]).to eq([1000, 500])
    expect(DeviceMinute.order(:bucket_ts).pluck(:uplink_bytes)).to eq([100, 900])
    expect(AgentFlowLifetime.count).to eq(1)
    expect(AgentFlowLifetime.first.closed_at).to eq(now + 65.seconds)
  end

  it "credits a destroy-only observation once even under a different receipt identity" do
    now = Time.current
    2.times do |index|
      expect(ingest(id: "end-#{index}", at: now, lifecycle: "Destroy", bytes: 1000)["accepted"]).to eq(1)
    end
    expect(DeviceMinute.sum(:uplink_bytes)).to eq(1000)
    expect(DeviceMinute.sum(:conn_count)).to eq(1)
    expect([NetmonEvent.count, AgentFlowLifetime.count]).to eq([2, 1])
  end

  it "starts a new legacy lifetime on NEW after DESTROY and clears tuple-cached DNS" do
    now = Time.current
    ingest(id: "a-new", at: now, lifecycle: "New", bytes: 100)
    ingest(id: "a-end", at: now + 1.second, lifecycle: "Destroy", bytes: 1000)
    Connection.first.update!(last_domain: "old.example", last_domain_observed_at: now)
    ingest(id: "b-new", at: now + 2.seconds, lifecycle: "New", bytes: 50)
    expect(Connection.first.first_seen_at).to eq(now + 2.seconds)
    expect(Connection.first.last_domain).to be_nil
    ingest(id: "b-end", at: now + 3.seconds, lifecycle: "Destroy", bytes: 200)
    expect([AgentFlowLifetime.count, DeviceMinute.sum(:conn_count), DeviceMinute.sum(:uplink_bytes)]).to eq([2, 2, 1200])
    expect(Connection.first.uplink_bytes).to eq(200)
  end

  it "accounts for an older identified lifetime without overwriting the newer tuple projection" do
    now = Time.current
    ingest(id: "a-new", flow_id: "A", at: now, lifecycle: "New", bytes: 100)
    ingest(id: "b-new", flow_id: "B", at: now + 2.seconds, lifecycle: "New", bytes: 50)
    ingest(id: "a-end", flow_id: "A", at: now + 1.second, lifecycle: "Destroy", bytes: 1000)
    expect([AgentFlowLifetime.count, DeviceMinute.sum(:conn_count), DeviceMinute.sum(:uplink_bytes)]).to eq([2, 2, 1050])
    expect(Connection.first.attributes.values_at("agent_flow_uid", "uplink_bytes", "last_seen_at")).to eq(["id:B", 50, now + 2.seconds])
  end

  it "detects a late completed lifetime without saving its score over the current flow" do
    now = Time.current
    ingest(id: "a-new", flow_id: "A", at: now, lifecycle: "New", bytes: 100)
    ingest(id: "b-new", flow_id: "B", at: now + 2.seconds, lifecycle: "New", bytes: 50)
    allow(Netmon::Anomaly::Scorer).to receive(:score_connection).and_return(score: 80, reasons: [{ code: "RARE_PORT", weight: 25 }])
    ingest(id: "a-end", flow_id: "A", at: now + 1.second, lifecycle: "Destroy", bytes: 1000)
    expect(AnomalyHit.where(alertable: true).count).to eq(1)
    expect(AnomalyHit.first.total_bytes).to eq(1500)
    expect(Incident.count).to eq(1)
    expect(Connection.first.attributes.values_at("agent_flow_uid", "anomaly_score")).to eq(["id:B", 0])
  end

  it "rejects a counter regression without lowering the stored baseline" do
    now = Time.current
    ingest(id: "a-new", flow_id: "A", at: now, lifecycle: "New", bytes: 100)
    result = ingest(id: "bad-reset", flow_id: "A", at: now + 1.second, lifecycle: "Update", bytes: 50)
    expect(result["results"]).to include(a_hash_including("status" => "rejected", "code" => "flow_counter_regression"))
    ingest(id: "a-end", flow_id: "A", at: now + 2.seconds, lifecycle: "Destroy", bytes: 200)
    expect(DeviceMinute.sum(:uplink_bytes)).to eq(200)
    expect(NetmonEvent.count).to eq(2)
  end

  it "rejects reuse of an explicit identity with a different tuple" do
    now = Time.current
    ingest(id: "a", flow_id: "A", at: now, lifecycle: "New", bytes: 100)
    result = ingest(id: "conflict", flow_id: "A", at: now + 1.second, lifecycle: "New", bytes: 100, port: 50001)
    expect(result["results"]).to include(a_hash_including("status" => "rejected", "code" => "flow_identity_conflict"))
    expect([NetmonEvent.count, AgentFlowLifetime.count, Connection.count]).to eq([1, 1, 1])
  end

  it "does not double count a late NEW after a provisional destroy-only legacy lifetime" do
    now = Time.current
    ingest(id: "end-first", at: now + 1.second, lifecycle: "Destroy", bytes: 1000)
    ingest(id: "late-new", at: now, lifecycle: "New", bytes: 100)
    expect([AgentFlowLifetime.count, DeviceMinute.sum(:conn_count), DeviceMinute.sum(:uplink_bytes)]).to eq([1, 1, 1000])
  end

  it "rolls back lifetime accounting and collector claims with failed normalization" do
    allow(Netmon::Anomaly::Scorer).to receive(:score_connection).and_raise("simulated detection failure")
    result = ingest(id: "failed", flow_id: "A", at: Time.current, lifecycle: "New", bytes: 100)
    expect(result["retryable"]).to eq(1)
    expect([NetmonEvent.count, AgentFlowLifetime.count, DeviceMinute.count, IngestSource.count]).to eq([0, 0, 0, 0])
  end

  it "retains a new raw event but skips older observations of an identified lifetime" do
    now = Time.current
    ingest(id: "newer", flow_id: "A", at: now + 1.second, lifecycle: "Update", bytes: 1000)
    ingest(id: "older", flow_id: "A", at: now, lifecycle: "New", bytes: 100)
    expect([NetmonEvent.count, AgentFlowLifetime.count, DeviceMinute.sum(:conn_count), DeviceMinute.sum(:uplink_bytes)]).to eq([2, 1, 1, 1000])
  end

  it "rejects a second flow collector while retaining its batch for operator recovery" do
    Netmon::RouterScope.bind_flow_collector!("router-1", "snapshot")
    result = ingest(id: "conflicting-collector", at: Time.current, lifecycle: "New", bytes: 100)
    expect(result["retryable"]).to eq(1)
    expect([NetmonEvent.count, AgentFlowLifetime.count, DeviceMinute.count]).to eq([0, 0, 0])
    expect(IngestSource.find(1).flow_collector).to eq("snapshot")
  end
end
