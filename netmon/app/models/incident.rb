# frozen_string_literal: true

class Incident < ApplicationRecord
  belongs_to :device, optional: true
  has_many :anomaly_hits, dependent: :nullify

  validates :fingerprint, :codes_csv, :first_seen_at, :last_seen_at, presence: true
end
