# frozen_string_literal: true

require "rails_helper"

RSpec.describe Netmon::Daemon do
  it "runs reconcile in a loop and sleeps between iterations" do
    allow(Netmon::ReconcileSnapshot).to receive(:run)
    allow(described_class).to receive(:sleep)

    described_class.run(interval: 0.0, max_iterations: 2)

    expect(Netmon::ReconcileSnapshot).to have_received(:run).twice
    expect(described_class).to have_received(:sleep).once
  end

  it "logs errors and keeps running" do
    logger = instance_double("Logger", error: nil)
    allow(Rails).to receive(:logger).and_return(logger)

    calls = 0
    allow(Netmon::ReconcileSnapshot).to receive(:run) do
      calls += 1
      raise "boom" if calls == 1
    end
    allow(described_class).to receive(:sleep)

    described_class.run(interval: 0.0, max_iterations: 2)

    expect(logger).to have_received(:error).with(/netmon daemon error/)
  end
end
