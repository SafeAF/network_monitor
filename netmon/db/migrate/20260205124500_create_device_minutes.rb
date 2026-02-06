# frozen_string_literal: true

class CreateDeviceMinutes < ActiveRecord::Migration[8.0]
  def change
    create_table :device_minutes do |t|
      t.references :device, null: false, foreign_key: true
      t.datetime :bucket_ts, null: false
      t.integer :conn_count, null: false, default: 0
      t.bigint :uplink_bytes, null: false, default: 0
      t.bigint :downlink_bytes, null: false, default: 0
      t.bigint :uplink_packets, null: false, default: 0
      t.bigint :downlink_packets, null: false, default: 0
      t.integer :new_dst_ips, null: false, default: 0
      t.integer :unique_dst_ips, null: false, default: 0
      t.integer :unique_dst_ports, null: false, default: 0
      t.integer :unique_dst_asns, null: false, default: 0
      t.integer :unique_protos, null: false, default: 0
      t.integer :rare_ports, null: false, default: 0
      t.timestamps
    end

    add_index :device_minutes, [:device_id, :bucket_ts], unique: true
    add_index :device_minutes, :bucket_ts
  end
end
