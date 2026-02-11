# frozen_string_literal: true

require "rails_helper"

RSpec.describe Netmon::IncidentFingerprint do
  it "removes NO_RDNS and sorts codes" do
    fp = described_class.build(
      device_id: 1,
      dst_ip: "203.0.113.10",
      dst_port: 443,
      proto: "tcp",
      codes: ["NO_RDNS", "RARE_PORT", "HIGH_EGRESS"]
    )

    expect(fp).to include("HIGH_EGRESS,RARE_PORT")
    expect(fp).not_to include("NO_RDNS")
  end

  it "uses required codes subset when provided" do
    fp = described_class.build(
      device_id: 1,
      dst_ip: "203.0.113.10",
      dst_port: 443,
      proto: "tcp",
      codes: ["RARE_PORT", "UNEXPECTED_PROTO", "NEW_DST"],
      required_codes: ["RARE_PORT", "HIGH_EGRESS"]
    )

    expect(fp).to end_with("RARE_PORT")
  end
end
