# frozen_string_literal: true

class SuppressionRulesController < ApplicationController
  def create
    rule = SuppressionRule.new(rule_params)
    if rule.save
      redirect_back fallback_location: "/"
    else
      render plain: rule.errors.full_messages.join(", "), status: :unprocessable_entity
    end
  end

  private

  def rule_params
    params.require(:suppression_rule).permit(:code, :kind, :value, :device_id, :notes)
  end
end
