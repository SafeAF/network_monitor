# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SavedQueries", type: :request do
  it "saves and loads params for a search page" do
    post "/saved_queries", params: {
      name: "My Hosts",
      path: "/search/hosts",
      kind: "hosts",
      params_json: { ip: "10.0.0." }.to_json
    }

    expect(response).to have_http_status(:found)
    saved = SavedQuery.last
    expect(saved.kind).to eq("hosts")
    expect(saved.params_hash["ip"]).to eq("10.0.0.")
  end

  it "rejects invalid JSON" do
    post "/saved_queries", params: {
      name: "Bad",
      path: "/search/hosts",
      kind: "hosts",
      params_json: "{bad json"
    }

    expect(response).to have_http_status(:unprocessable_entity)
  end
end
