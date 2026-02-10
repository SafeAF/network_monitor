# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Search pages", type: :request do
  it "renders hosts search" do
    get "/search/hosts"
    expect(response).to have_http_status(:ok)
  end

  it "renders connections search" do
    get "/search/connections"
    expect(response).to have_http_status(:ok)
  end

  it "renders anomalies search" do
    get "/search/anomalies"
    expect(response).to have_http_status(:ok)
  end
end
