# frozen_string_literal: true

# This installation supports one router until normalized identities are scoped.
class IngestSource < ApplicationRecord
  validates :id, inclusion: { in: [1] }
  validates :router_id, format: { with: Netmon::RouterPolicy::ID_PATTERN }
end
