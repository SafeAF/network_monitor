# frozen_string_literal: true

class DnsEventAnswer < ApplicationRecord
  belongs_to :dns_event

  validates :answer_ip, :answer_type, presence: true
end
