# frozen_string_literal: true

class AllowlistRule < ApplicationRecord
  KINDS = %w[asn org rdns_suffix ip port device_port].freeze

  belongs_to :device, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :value, presence: true

  def self.match?(kind:, value:, device_id: nil)
    scope = where(kind: kind, value: value)
    return scope.exists? if device_id.nil?

    scope.where(device_id: [nil, device_id]).exists?
  end
end
