# frozen_string_literal: true

class AllowlistRulesController < ApplicationController
  def create
    rule = AllowlistRule.new(rule_params)
    if rule.save
      redirect_back fallback_location: "/"
    else
      render plain: rule.errors.full_messages.join(", "), status: :unprocessable_entity
    end
  end

  private

  def rule_params
    params.require(:allowlist_rule).permit(:kind, :value, :device_id, :notes)
  end
end
