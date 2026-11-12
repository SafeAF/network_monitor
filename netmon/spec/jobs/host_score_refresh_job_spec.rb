# frozen_string_literal: true

require "rails_helper"

RSpec.describe HostScoreRefreshJob do
  include ActiveJob::TestHelper

  around do |example|
    previous = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = previous
  end

  it "bounds each pass and fixes the scan endpoint before following batches" do
    now = Time.current
    host = RemoteHost.create!(ip: "203.0.113.8", first_seen_at: now, last_seen_at: now)
    Device.create!(ip: "10.0.0.20", name: "client", first_seen_at: now, last_seen_at: now)
    101.times do |index|
      Connection.create!(proto: "tcp", src_ip: "10.0.0.20", src_port: index + 1,
        dst_ip: host.ip, dst_port: 443, first_seen_at: now, last_seen_at: now)
    end
    endpoint = Connection.maximum(:id)
    Connection.create!(proto: "tcp", src_ip: "10.0.0.20", src_port: 102,
      dst_ip: host.ip, dst_port: 443, first_seen_at: now, last_seen_at: now)
    allow(Netmon::Anomaly::Detection).to receive(:call)
    expect { described_class.perform_now(host.id, 0, endpoint) }.to have_enqueued_job(described_class)
    expect(Netmon::Anomaly::Detection).to have_received(:call).exactly(100).times
    cursor = Connection.order(:id).offset(99).first.id
    described_class.perform_now(host.id, cursor, endpoint)
    expect(Netmon::Anomaly::Detection).to have_received(:call).exactly(101).times
  end
end
