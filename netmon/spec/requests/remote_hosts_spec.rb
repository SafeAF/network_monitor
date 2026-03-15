# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Remote hosts", type: :request do
  it "shows recent associated domains on the remote host page" do
    host = RemoteHost.create!(
      ip: "203.0.113.30",
      first_seen_at: 2.hours.ago,
      last_seen_at: 1.minute.ago
    )
    RemoteHostDomain.create!(
      remote_host: host,
      domain: "api.github.com",
      first_seen_at: 30.minutes.ago,
      last_seen_at: 5.minutes.ago,
      seen_count: 4,
      last_device_ip: "10.0.0.42"
    )

    get "/remote_hosts/#{host.ip}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Recent Domains")
    expect(response.body).to include("api.github.com")
    expect(response.body).to include("10.0.0.42")
  end
end
