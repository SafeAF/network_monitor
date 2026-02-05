# frozen_string_literal: true

class Connection < ApplicationRecord
  validates :proto, :src_ip, :dst_ip, presence: true
end
