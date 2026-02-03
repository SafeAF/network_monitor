# frozen_string_literal: true

require "rails_helper"

RSpec.describe Conntrack::Key do
  it "builds a stable 5-tuple key from an entry" do
    line = "ipv4 2 tcp 6 1 TIME_WAIT src=10.0.0.24 dst=142.250.69.174 sport=40098 dport=443 packets=67 bytes=10475 src=142.250.69.174 dst=135.131.124.247 sport=443 dport=40098 packets=68 bytes=17170 [ASSURED] mark=0 use=1"
    entry = Conntrack::Parser.parse_line(line)

    key = described_class.from_entry(entry)
    expect(key).to eq("tcp|10.0.0.24|40098|142.250.69.174|443")
  end

  it "returns nil for nil entries" do
    expect(described_class.from_entry(nil)).to be_nil
  end
end
