# frozen_string_literal: true

require "rails_helper"

RSpec.describe Netmon::Filter do
  let(:fixture_lines) do
    path = Rails.root.join("spec/fixtures/conntrack/router_extended.txt")
    File.readlines(path, chomp: true)
  end

  it "returns true for outbound entries" do
    line = fixture_lines.find { |l| l.include?("dst=192.82.242.219") }
    entry = Conntrack::Parser.parse_line(line)

    expect(described_class.outbound?(entry)).to eq(true)
  end

  it "returns false for entries to private destinations" do
    line = fixture_lines.find { |l| l.include?("dst=10.0.0.1") }
    entry = Conntrack::Parser.parse_line(line)

    expect(described_class.outbound?(entry)).to eq(false)
  end
end
