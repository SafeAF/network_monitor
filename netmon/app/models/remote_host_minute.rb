# frozen_string_literal: true

class RemoteHostMinute < ApplicationRecord
  belongs_to :remote_host

  validates :bucket_ts, presence: true
end
