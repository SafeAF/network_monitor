# frozen_string_literal: true

class AddConnectionDstIpIndexes < ActiveRecord::Migration[8.0]
  def change
    add_index :connections, :dst_ip, if_not_exists: true
    add_index :connections, [:dst_ip, :last_seen_at], if_not_exists: true
  end
end
