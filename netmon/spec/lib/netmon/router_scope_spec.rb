# frozen_string_literal: true

require "rails_helper"

RSpec.describe Netmon::RouterScope do
  it "preserves the binding when all receipts have been pruned" do
    described_class.bind!("router-1")
    NetmonEvent.delete_all
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("NETMON_ROUTER_ID", "").and_return("router-2")

    expect { described_class.bind!("router-2") }.to raise_error(Netmon::RouterPolicy::Unavailable, "router_binding_conflict")
    expect(IngestSource.find(1).router_id).to eq("router-1")
  end

  it "enforces the single-row binding in the database" do
    described_class.bind!("router-1")
    expect do
      IngestSource.insert_all!([{ id: 2, router_id: "router-2", created_at: Time.current, updated_at: Time.current }])
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(IngestSource.count).to eq(1)
  end
end
