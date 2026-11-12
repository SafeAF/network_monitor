# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Operator security", type: :request, operator_auth: false do
  def authorization(role = "admin")
    { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(
      "test-#{role}", "test-#{role}-password-123456") }
  end

  it "denies anonymous telemetry reads and writes" do
    get "/connections.json"
    expect(response).to have_http_status(:unauthorized)
    expect(response.headers["WWW-Authenticate"]).to include("Basic")
    post "/suppression_rules", params: { suppression_rule: { code: "NO_RDNS", kind: "ip", value: "203.0.113.8" } }
    expect(response).to have_http_status(:unauthorized)
    expect(SuppressionRule.count).to eq(0)
  end

  it "denies operator access when credentials are missing" do
    ENV.delete("NETMON_ADMIN_PASSWORD")
    get "/connections.json", headers: authorization
    expect(response).to have_http_status(:unauthorized)
  end

  it "allows reader telemetry access but denies changes" do
    get "/connections.json", headers: authorization("reader")
    expect(response).to have_http_status(:ok)
    post "/allowlist_rules", headers: authorization("reader"), params: { allowlist_rule: { kind: "ip", value: "203.0.113.8" } }
    expect(response).to have_http_status(:forbidden)
    expect(AllowlistRule.count).to eq(0)
  end

  it "keeps agent and operator credentials separate" do
    previous = ENV["NETMON_API_TOKEN"]
    ENV["NETMON_API_TOKEN"] = "test-agent-token"
    begin
      get "/connections.json", headers: { "Authorization" => "Bearer test-agent-token" }
      expect(response).to have_http_status(:unauthorized)
      post "/api/v1/netmon/events/batch", headers: authorization, params: { router_id: "router-1", events: [] }, as: :json
      expect(response).to have_http_status(:unauthorized)
      post "/api/v1/netmon/events/batch", headers: { "Authorization" => "Bearer test-agent-token" }, params: { router_id: "router-1", events: [] }, as: :json
      expect(response).to have_http_status(:ok)
    ensure
      previous.nil? ? ENV.delete("NETMON_API_TOKEN") : ENV["NETMON_API_TOKEN"] = previous
    end
  end

  it "audits authorized changes without logging note values" do
    messages = []
    allow(Rails.logger).to receive(:info) { |message| messages << message }
    post "/allowlist_rules", headers: authorization,
      params: { allowlist_rule: { kind: "ip", value: "203.0.113.8", notes: "private operator note" } }
    expect(response).to have_http_status(:redirect)
    audit = messages.filter_map { |message| JSON.parse(message.to_s) rescue nil }.find { |message| message["event"] == "operator_change" }
    expect(audit).to include("actor" => "test-admin", "action" => "create")
    expect(audit.to_json).not_to include("private operator note")
  end

  it "preserves browser CSRF protection on mutations" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    begin
      post "/allowlist_rules", headers: authorization, params: { allowlist_rule: { kind: "ip", value: "203.0.113.8" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(AllowlistRule.count).to eq(0)
    ensure
      ActionController::Base.allow_forgery_protection = previous
    end
  end
end
