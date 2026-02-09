# frozen_string_literal: true

class AnomalyHit < ApplicationRecord
  belongs_to :device
  belongs_to :remote_host, optional: true

  validates :occurred_at, presence: true
  validates :reasons_json, presence: true

  def reasons
    JSON.parse(reasons_json || "[]")
  rescue JSON::ParserError
    []
  end

  def reason_codes
    reasons.map { |reason| reason["code"] }.compact
  end
end
