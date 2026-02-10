# frozen_string_literal: true

class SuppressionRule < ApplicationRecord
  KINDS = %w[asn org rdns_suffix ip port device_port].freeze

  belongs_to :device, optional: true

  validates :code, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :value, presence: true

  def self.match?(code:, kind:, value:, device_id: nil)
    scope = where(code: code, kind: kind, value: value)
    return scope.exists? if device_id.nil?

    scope.where(device_id: [nil, device_id]).exists?
  end
end
