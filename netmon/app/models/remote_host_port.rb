# frozen_string_literal: true

class RemoteHostPort < ApplicationRecord
  belongs_to :remote_host

  validates :port, presence: true
  validates :first_seen_at, presence: true
  validates :last_seen_at, presence: true
end
