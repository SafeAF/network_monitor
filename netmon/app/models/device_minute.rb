# frozen_string_literal: true

class DeviceMinute < ApplicationRecord
  belongs_to :device

  validates :bucket_ts, presence: true
end
