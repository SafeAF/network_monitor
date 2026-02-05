# frozen_string_literal: true

class CreateConnections < ActiveRecord::Migration[8.0]
  def change
    create_table :connections do |t|
      t.string :proto, null: false
      t.string :src_ip, null: false
      t.integer :src_port
      t.string :dst_ip, null: false
      t.integer :dst_port
      t.string :state
      t.string :flags
      t.bigint :uplink_packets, null: false, default: 0
      t.bigint :uplink_bytes, null: false, default: 0
      t.bigint :downlink_packets, null: false, default: 0
      t.bigint :downlink_bytes, null: false, default: 0
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
    end

    add_index :connections,
              %i[proto src_ip src_port dst_ip dst_port],
              unique: true,
              name: "index_connections_on_5_tuple"
  end
end
