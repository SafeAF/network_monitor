# frozen_string_literal: true

class UpdateRemoteHostPorts < ActiveRecord::Migration[8.0]
  def change
    rename_column :remote_host_ports, :port, :dst_port
    add_column :remote_host_ports, :seen_count, :integer, null: false, default: 0
    remove_index :remote_host_ports, name: "index_remote_host_ports_on_remote_host_id_and_port", if_exists: true
    add_index :remote_host_ports, [:remote_host_id, :dst_port], unique: true, name: "index_remote_host_ports_on_remote_host_id_and_dst_port", if_not_exists: true
  end
end
