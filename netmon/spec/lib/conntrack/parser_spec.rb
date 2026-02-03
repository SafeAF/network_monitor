# frozen_string_literal: true

require "rails_helper"

RSpec.describe Conntrack::Parser do
  let(:fixture_lines) do
    path = Rails.root.join("spec/fixtures/conntrack/router_extended.txt")
    File.readlines(path, chomp: true)
  end

  it "parses tcp with state and counters" do
    line = fixture_lines.find { |l| l.include?("packets=") }
    entry = described_class.parse_line(line)

    expect(entry).not_to be_nil
    expect(entry.proto).to eq("tcp")
    expect(entry.state).not_to be_nil
    expect(entry.orig.src).to start_with("10.0.0.")
    expect(entry.orig.packets).to be > 0
    expect(entry.reply.packets).to be > 0
    expect(entry.flags).to include("ASSURED")
  end

  it "parses tcp with state but without counters" do
    line = fixture_lines.find { |l| !l.include?("packets=") }
    entry = described_class.parse_line(line)

    expect(entry).not_to be_nil
    expect(entry.proto).to eq("tcp")
    expect(entry.state).not_to be_nil
    expect(entry.orig.packets).to eq(0)
    expect(entry.reply.packets).to eq(0)
  end

  it "parses udp without state and counters" do
    line = "ipv4 2 udp 17 12 src=10.0.0.24 dst=34.111.60.239 sport=54756 dport=443 packets=23 bytes=3538 src=34.111.60.239 dst=135.131.124.247 sport=443 dport=54756 packets=77 bytes=101240 mark=0 use=1"
    entry = described_class.parse_line(line)

    expect(entry).not_to be_nil
    expect(entry.proto).to eq("udp")
    expect(entry.state).to be_nil
    expect(entry.flags).to be_empty
    expect(entry.orig.bytes).to eq(3538)
    expect(entry.reply.bytes).to eq(101_240)
  end

  it "returns nil when tuples are missing" do
    line = "ipv4 2 tcp 6 431977 ESTABLISHED src=10.0.0.24 dst=192.82.242.219 sport=60004 dport=443"
    entry = described_class.parse_line(line)

    expect(entry).to be_nil
  end
end
