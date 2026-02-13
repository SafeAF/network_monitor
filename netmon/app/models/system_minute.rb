# frozen_string_literal: true

class SystemMinute < ApplicationRecord
  validates :bucket_ts, presence: true
end
