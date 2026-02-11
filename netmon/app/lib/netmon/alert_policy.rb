# frozen_string_literal: true

module Netmon
  module AlertPolicy
    Result = Struct.new(:alertable, :codes, :required_codes, :suppress_only_codes, keyword_init: true)

    def self.evaluate(reasons:, score:, config:)
      alert_config = config.fetch("alert", {})
      threshold = (alert_config["threshold_score"] || 70).to_i
      required_codes = Array(alert_config["required_codes"]).map(&:to_s)
      suppress_only_codes = Array(alert_config["suppress_if_only_codes"]).map(&:to_s)

      codes = Array(reasons).map { |reason| reason[:code] || reason["code"] }.compact.map(&:to_s)
      has_required = required_codes.empty? ? true : (codes & required_codes).any?
      suppress_only = suppress_only_codes.any? && (codes - suppress_only_codes).empty?

      alertable = score.to_i >= threshold && has_required && !suppress_only

      Result.new(
        alertable:,
        codes:,
        required_codes:,
        suppress_only_codes:
      )
    end
  end
end
