# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Metrics JSON", type: :request do
  it "returns metrics payload" do
    payload = {
      timestamp: "2026-02-05T12:00:00Z",
      loadavg: { one: 0.1, five: 0.2, fifteen: 0.3 },
      meminfo: { total_kb: 100, free_kb: 10, available_kb: 20, buffers_kb: 5, cached_kb: 15 },
      interfaces: [{ name: "eth0", rx_bytes: 1, tx_bytes: 2, rx_packets: 3, tx_packets: 4 }],
      analytics: {
        new_dst_ips_last_10m: 1,
        unique_dports_last_10m: 2,
        uplink_bytes_last_10m: 300,
        baseline_p95_uplink_bytes_last_10m: 100,
        new_asns_last_1h: 1,
        new_asns_list: ["AS64512"],
        anomalies: []
      },
      series: {
        timestamps: ["2026-02-05T11:59:00Z"],
        new_dst_ips_last_10m: [1],
        unique_dports_last_10m: [2],
        uplink_bytes_last_10m: [300],
        baseline_p95_uplink_bytes_last_10m: [100],
        new_asns_last_1h: [1]
      }
    }

    allow(Netmon::Metrics).to receive(:read).and_return(payload)

    get "/metrics.json"

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["timestamp"]).to eq("2026-02-05T12:00:00Z")
    expect(body["loadavg"]["one"]).to eq(0.1)
    expect(body["interfaces"].first["name"]).to eq("eth0")
    expect(body["analytics"]["new_dst_ips_last_10m"]).to eq(1)
    expect(body["series"]["new_asns_last_1h"]).to eq([1])
  end
end
