# frozen_string_literal: true

class Device < ApplicationRecord
  validates :ip, presence: true, uniqueness: true
  validates :name, presence: true
end
