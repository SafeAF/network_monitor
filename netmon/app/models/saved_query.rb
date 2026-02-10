# frozen_string_literal: true

require "json"

class SavedQuery < ApplicationRecord
  KINDS = %w[hosts connections anomalies].freeze

  validates :name, presence: true
  validates :path, presence: true
  validates :params_json, presence: true
  validates :kind, inclusion: { in: KINDS }
  validate :params_json_must_be_valid

  def params_hash
    JSON.parse(params_json || "{}")
  rescue JSON::ParserError
    {}
  end

  def params_json_must_be_valid
    JSON.parse(params_json || "{}")
  rescue JSON::ParserError
    errors.add(:params_json, "is invalid JSON")
  end
end
