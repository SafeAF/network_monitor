# frozen_string_literal: true

require "json"

class SavedQuery < ApplicationRecord
  validates :name, presence: true
  validates :path, presence: true
  validates :params_json, presence: true

  def params_hash
    JSON.parse(params_json || "{}")
  rescue JSON::ParserError
    {}
  end
end
