# frozen_string_literal: true

class MetricSample < ApplicationRecord
  validates :captured_at, presence: true
end
