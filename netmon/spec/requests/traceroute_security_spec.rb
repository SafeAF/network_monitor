# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Traceroute security", type: :request do
  include ActiveJob::TestHelper

  around do |example|
    previous = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    begin
      example.run
    ensure
      ActiveJob::Base.queue_adapter = previous
    end
  end

  before do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    RemoteHost.create!(ip: "203.0.113.8", first_seen_at: Time.current, last_seen_at: Time.current)
  end

  it "never starts or cancels probes through GET" do
    expect { get "/remote_hosts/203.0.113.8/traceroute.json", params: { start: 1, cancel: 1 } }
      .not_to have_enqueued_job(TracerouteJob)
    expect(JSON.parse(response.body)["status"]).to eq("idle")
    expect(Rails.cache.read("traceroute:203.0.113.8")).to be_nil
  end

  it "starts an observed literal IP with POST and cancels with DELETE" do
    expect { post "/remote_hosts/203.0.113.8/traceroute.json" }.to have_enqueued_job(TracerouteJob)
    expect(response).to have_http_status(:accepted)
    delete "/remote_hosts/203.0.113.8/traceroute.json"
    expect(JSON.parse(response.body)["status"]).to eq("cancelled")
  end

  it "rejects hostnames and utility options" do
    %w[localhost -V].each do |target|
      expect { post "/remote_hosts/#{target}/traceroute.json" }.not_to have_enqueued_job(TracerouteJob)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it "rejects unobserved addresses and duplicate queued probes" do
    post "/remote_hosts/203.0.113.99/traceroute.json"
    expect(response).to have_http_status(:not_found)
    post "/remote_hosts/203.0.113.8/traceroute.json"
    expect { post "/remote_hosts/203.0.113.8/traceroute.json" }.not_to have_enqueued_job(TracerouteJob)
    expect(response).to have_http_status(:conflict)
  end
end
