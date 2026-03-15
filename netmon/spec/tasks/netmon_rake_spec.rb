# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "netmon rake tasks" do
  before(:all) do
    Rake.application = Rake::Application.new
    Rails.application.load_tasks
  end

  after(:all) do
    Rake.application = nil
  end

  before do
    Rake::Task["netmon:dns_prune"].reenable
  end

  it "prunes old raw DNS rows via netmon:dns_prune" do
    now = Time.zone.parse("2026-03-15 12:00:00")
    allow(Time).to receive(:current).and_return(now)

    old_event = DnsEvent.create!(
      router_id: "router-1",
      observed_at: now - 31.days,
      client_ip: "10.0.0.20",
      qname: "api.github.com",
      qtype: "A",
      answers_json: ["203.0.113.44"].to_json,
      dedupe_key: "task-old-key"
    )
    old_answer = DnsEventAnswer.create!(
      dns_event: old_event,
      answer_ip: "203.0.113.44",
      answer_type: "A"
    )
    fresh_event = DnsEvent.create!(
      router_id: "router-1",
      observed_at: now - 1.day,
      client_ip: "10.0.0.21",
      qname: "cdn.cloudflare.net",
      qtype: "A",
      answers_json: ["198.51.100.10"].to_json,
      dedupe_key: "task-fresh-key"
    )

    expect do
      Rake::Task["netmon:dns_prune"].invoke
    end.to output(/dns_events_deleted=1 dns_event_answers_deleted=1/).to_stdout

    expect(DnsEvent.exists?(old_event.id)).to eq(false)
    expect(DnsEventAnswer.exists?(old_answer.id)).to eq(false)
    expect(DnsEvent.exists?(fresh_event.id)).to eq(true)
  end
end
