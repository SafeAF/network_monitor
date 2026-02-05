# frozen_string_literal: true

class RemoteHost < ApplicationRecord
  validates :ip, presence: true, uniqueness: true
end
