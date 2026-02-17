# frozen_string_literal: true

class AddSearchIndexes < ActiveRecord::Migration[8.0]
  def change
    add_index :remote_hosts, [:tag, :last_seen_at], if_not_exists: true
    add_index :remote_hosts, :whois_asn, if_not_exists: true
  end
end
