# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Agent detection and snapshot parity", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:config) do
    { "anomaly_threshold" => 50, "dedup_suppress_seconds" => 600,
      "alert" => { "threshold_score" => 70, "required_codes" => ["RARE_PORT"],
        "suppress_if_only_codes" => ["NO_RDNS"], "incident_window_seconds" => 600 } }
  end
  let(:host) do
    RemoteHost.create!(ip: "203.0.113.8", first_seen_at: Time.current - 30.seconds,
      last_seen_at: Time.current, whois_name: "Example Org", whois_asn: "AS64512",
      rdns_checked_at: Time.current, whois_checked_at: Time.current)
  end

  around do |example|
    previous = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    travel_to(Time.zone.parse("2026-11-12T12:00:00Z")) { example.run }
  ensure
    ActiveJob::Base.queue_adapter = previous
  end

  before do
    host
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("NETMON_API_TOKEN", "").and_return("test-token")
    allow(Netmon::Anomaly::Scorer).to receive(:configuration).and_return(config)
    allow(Netmon::ReconcileSnapshot).to receive(:load_config).and_return(config)
    allow(Netmon::HostEnricher).to receive(:apply)
  end

  def ingest(id: "event-1", src: "10.0.0.20", bytes: 100, state: "NEW")
    payload = { router_id: "router-1", events: [{ id: id, type: "flow", ts: Time.current.iso8601,
      data: { src_ip: src, dst_ip: host.ip, src_port: 50000, dst_port: 4444,
        l4proto: 6, state: state, bytes_orig: bytes, bytes_reply: 50, packets_orig: 2, packets_reply: 1 } }] }
    post "/api/v1/netmon/events/batch", params: payload, as: :json,
      headers: { "Authorization" => "Bearer test-token", "X-Netmon-Protocol-Version" => "1" }
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["accepted"]).to eq(1)
  end

  it "creates alertable hits and incidents through the agent path and deduplicates replay" do
    ingest
    expect(Incident.count).to eq(1)
    expect(AnomalyHit.where(alertable: true).count).to eq(1)
    expect(AnomalyHit.first.reason_codes).to include("RARE_PORT", "NEW_ASN")
    ingest
    expect([NetmonEvent.count, AnomalyHit.count, Incident.first.count]).to eq([1, 1, 1])
  end

  it "keeps WAN-source observations raw instead of creating internal device incidents" do
    ingest(src: "198.51.100.99")
    expect(NetmonEvent.count).to eq(1)
    expect([Device.count, Connection.count, AnomalyHit.count, Incident.count]).to eq([0, 0, 0, 0])
  end

  it "detects high egress on the terminal update using the just-written delta" do
    config["alert"]["required_codes"] = ["HIGH_EGRESS"]
    device = Device.create!(ip: "10.0.0.20", name: "client", first_seen_at: 1.day.ago, last_seen_at: Time.current)
    DeviceBaseline.create!(device_id: device.id, p95_uplink_bytes_per_min: 1)
    ingest
    expect(Incident.count).to eq(0)
    travel 5.seconds
    ingest(id: "terminal-event", bytes: 10000, state: "DESTROY")
    expect(Incident.count).to eq(1)
    expect(AnomalyHit.where(alertable: true).first.reason_codes).to include("HIGH_EGRESS")
    expect(DeviceMinute.sum(:uplink_bytes)).to eq(9900)
  end

  it "uses the same score, hit and incident policy in snapshot ingestion" do
    orig = Conntrack::Tuple.new(src: "10.0.0.21", dst: host.ip, sport: 50000, dport: 4444, bytes: 100, packets: 2)
    reply = Conntrack::Tuple.new(src: host.ip, dst: "10.0.0.21", sport: 4444, dport: 50000, bytes: 50, packets: 1)
    entry = Conntrack::Entry.new(family: "ipv4", proto: "tcp", state: "NEW", orig: orig, reply: reply, flags: [])
    allow(Conntrack::Snapshot).to receive(:read).and_return([entry])
    Netmon::ReconcileSnapshot.run(input_file: nil, now: Time.current)
    ingest
    snapshot = Connection.find_by!(src_ip: "10.0.0.21")
    agent = Connection.find_by!(src_ip: "10.0.0.20")
    expect(agent.anomaly_score).to eq(snapshot.anomaly_score)
    expect(JSON.parse(agent.anomaly_reasons_json)).to eq(JSON.parse(snapshot.anomaly_reasons_json))
    expect(AnomalyHit.where(alertable: true).count).to eq(2)
    expect(Incident.count).to eq(2)
  end

  it "respects allowlists and suppression rules for agent observations" do
    AllowlistRule.create!(kind: "ip", value: host.ip)
    ingest
    expect(Connection.first.anomaly_score).to eq(0)
    expect([AnomalyHit.count, Incident.count]).to eq([0, 0])
    AllowlistRule.delete_all
    SuppressionRule.create!(code: "RARE_PORT", kind: "ip", value: host.ip)
    travel 1.second
    ingest(id: "after-suppression", state: "DESTROY")
    expect(Incident.count).to eq(0)
    expect(JSON.parse(Connection.first.anomaly_reasons_json).map { |reason| reason["code"] }).not_to include("RARE_PORT")
  end

  it "emits device-level fanout hits even without agent minute novelty counters" do
    config["anomaly_threshold"] = 100
    config["high_fanout_threshold"] = 2
    config["alert"]["required_codes"] = ["HIGH_FANOUT"]
    Device.create!(ip: "10.0.0.20", name: "client", first_seen_at: 1.day.ago, last_seen_at: Time.current)
    2.times do |index|
      ip = "198.51.100.#{index + 1}"
      RemoteHost.create!(ip: ip, first_seen_at: 5.seconds.ago, last_seen_at: Time.current)
      Connection.create!(proto: "tcp", src_ip: "10.0.0.20", src_port: 4000 + index,
        dst_ip: ip, dst_port: 443, first_seen_at: Time.current, last_seen_at: Time.current)
    end
    ingest
    expect(AnomalyHit.where(summary: "HIGH_FANOUT", dst_ip: nil).count).to eq(1)
    expect(Incident.where(dst_ip: nil).count).to eq(1)
  end

  it "refreshes scores after enrichment without applying traffic twice" do
    host.update!(whois_name: nil, whois_asn: nil)
    ingest
    expect(Incident.count).to eq(0)
    counters = [DeviceMinute.sum(:conn_count), DeviceMinute.sum(:uplink_bytes)]
    host.update!(whois_name: "Example Org", whois_asn: "AS64512")
    HostScoreRefreshJob.perform_now(host.id)
    expect(Incident.count).to eq(1)
    expect([DeviceMinute.sum(:conn_count), DeviceMinute.sum(:uplink_bytes)]).to eq(counters)
  end

  it "rolls back a receipt and all normalized state if incident persistence fails" do
    allow(Incident).to receive(:create!).and_raise("simulated incident failure")
    post "/api/v1/netmon/events/batch", params: { router_id: "r", events: [{ id: "failed-event", type: "flow",
      ts: Time.current.iso8601, data: { src_ip: "10.0.0.20", dst_ip: host.ip, src_port: 50000, dst_port: 4444, l4proto: 6 } }] },
      as: :json, headers: { "Authorization" => "Bearer test-token", "X-Netmon-Protocol-Version" => "1" }
    expect(JSON.parse(response.body)["retryable"]).to eq(1)
    expect([NetmonEvent.count, Connection.count, AnomalyHit.count, Incident.count, DeviceMinute.count]).to eq([0, 0, 0, 0, 0])
  end
end
