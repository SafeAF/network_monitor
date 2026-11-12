# frozen_string_literal: true

require "rails_helper"

RSpec.describe PruneNetmonEventsJob do
  it "keeps receipt identities throughout the replay window and removes older receipts" do
    old = NetmonEvent.create!(router_id: "r", event_type: "heartbeat", ts: 40.days.ago, data: {}, created_at: 36.days.ago)
    recent = NetmonEvent.create!(router_id: "r", event_type: "heartbeat", ts: 40.days.ago, data: {}, created_at: 1.day.ago)
    window = NetmonEvent.create!(router_id: "r", event_type: "heartbeat", ts: 30.days.ago, data: {}, created_at: 30.days.ago)
    described_class.perform_now
    expect(NetmonEvent.exists?(old.id)).to be(false)
    expect(NetmonEvent.exists?(recent.id)).to be(true)
    expect(NetmonEvent.exists?(window.id)).to be(true)
  end

  it "keeps open and recently observed lifetimes but prunes old closed counter state" do
    attributes = { router_id: "router-1", tuple_key: "tuple", first_observed_at: 40.days.ago }
    old = AgentFlowLifetime.create!(**attributes, flow_uid: "old", last_observed_at: 36.days.ago, closed_at: 36.days.ago)
    recent = AgentFlowLifetime.create!(**attributes, flow_uid: "recent", last_observed_at: 1.day.ago, closed_at: 36.days.ago)
    active = AgentFlowLifetime.create!(**attributes, flow_uid: "active", last_observed_at: 36.days.ago)
    described_class.perform_now
    expect(AgentFlowLifetime.exists?(old.id)).to be(false)
    expect(AgentFlowLifetime.exists?(recent.id)).to be(true)
    expect(AgentFlowLifetime.exists?(active.id)).to be(true)
  end
end
