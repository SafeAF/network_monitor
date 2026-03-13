# frozen_string_literal: true

class DnsEvent < ApplicationRecord
  has_many :dns_event_answers, dependent: :destroy

  validates :router_id, :observed_at, :client_ip, :qname, :qtype, :dedupe_key, presence: true
  validates :dedupe_key, uniqueness: true

  def answers
    JSON.parse(answers_json)
  rescue JSON::ParserError, TypeError
    []
  end
end
