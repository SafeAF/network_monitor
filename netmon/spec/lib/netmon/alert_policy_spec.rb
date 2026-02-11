# frozen_string_literal: true

require "rails_helper"

RSpec.describe Netmon::AlertPolicy do
  it "marks alertable when above threshold and has required code" do
    result = described_class.evaluate(
      reasons: [{ code: "RARE_PORT", weight: 25 }],
      score: 80,
      config: {
        "alert" => {
          "threshold_score" => 70,
          "required_codes" => ["RARE_PORT"],
          "suppress_if_only_codes" => ["NO_RDNS"]
        }
      }
    )

    expect(result.alertable).to eq(true)
  end

  it "suppresses NO_RDNS-only alerts" do
    result = described_class.evaluate(
      reasons: [{ code: "NO_RDNS", weight: 10 }],
      score: 90,
      config: {
        "alert" => {
          "threshold_score" => 70,
          "required_codes" => ["RARE_PORT"],
          "suppress_if_only_codes" => ["NO_RDNS"]
        }
      }
    )

    expect(result.alertable).to eq(false)
  end
end
