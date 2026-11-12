# frozen_string_literal: true

class Device < ApplicationRecord
  validates :ip, presence: true, uniqueness: true
  validates :name, presence: true
  validates :name, length: { maximum: 255 }
  validates :notes, length: { maximum: 10_000 }
end
