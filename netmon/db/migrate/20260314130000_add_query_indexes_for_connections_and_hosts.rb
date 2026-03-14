# frozen_string_literal: true

class AddQueryIndexesForConnectionsAndHosts < ActiveRecord::Migration[8.0]
  def change
    add_index :connections, :src_ip, if_not_exists: true
    add_index :connections, [:src_ip, :last_seen_at], if_not_exists: true
    add_index :connections, [:src_ip, :dst_ip], if_not_exists: true

    add_index :remote_hosts, :rdns_name, if_not_exists: true
    add_index :remote_hosts, :whois_name, if_not_exists: true
  end
end
