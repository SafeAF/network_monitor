# frozen_string_literal: true

class AddPerformanceIndexes < ActiveRecord::Migration[8.0]
  def change
    add_index :remote_hosts, :last_seen_at, if_not_exists: true
    add_index :remote_hosts, :first_seen_at, if_not_exists: true

    add_index :connections, :last_seen_at, if_not_exists: true
    add_index :connections, :anomaly_score, if_not_exists: true

    add_index :anomaly_hits, :occurred_at, if_not_exists: true
    add_index :anomaly_hits, :score, if_not_exists: true
    add_index :anomaly_hits, :dst_ip, if_not_exists: true

    add_index :remote_host_ports, [:remote_host_id, :dst_port], name: "index_remote_host_ports_on_remote_host_id_and_dst_port", if_not_exists: true
    add_index :remote_host_ports, :last_seen_at, if_not_exists: true

    add_index :devices, :ip, if_not_exists: true
    add_index :devices, :name, if_not_exists: true
  end
end
