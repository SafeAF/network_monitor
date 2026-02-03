# frozen_string_literal: true

require "rails_helper"

RSpec.describe Conntrack::Snapshot do
  let(:fixture_lines) do
    path = Rails.root.join("spec/fixtures/conntrack/router_extended.txt")
    File.readlines(path, chomp: true)
  end

  it "parses snapshot output into entries" do
    output = [fixture_lines[0], fixture_lines[1]].join("\n")
    entries = described_class.read(output: output, input_file: nil)

    expect(entries.length).to eq(2)
    expect(entries.first).to be_a(Conntrack::Entry)
  end

  it "raises when the snapshot command fails" do
    status = instance_double(Process::Status, success?: false)
    runner = instance_double("Runner")
    allow(runner).to receive(:capture2e).and_return(["boom", status])

    expect do
      described_class.read(command: ["conntrack"], runner: runner, input_file: nil)
    end.to raise_error(/conntrack snapshot failed/)
  end
end
