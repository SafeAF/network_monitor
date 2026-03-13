# frozen_string_literal: true

class RemoteHostDomain < ApplicationRecord
  belongs_to :remote_host

  validates :domain, :first_seen_at, :last_seen_at, presence: true
  validates :domain, uniqueness: { scope: :remote_host_id }
end
