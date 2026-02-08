# frozen_string_literal: true

class DeviceBaseline < ApplicationRecord
  belongs_to :device

  validates :window_minutes, presence: true
end
