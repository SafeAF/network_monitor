# frozen_string_literal: true

class CreateDeviceBaselines < ActiveRecord::Migration[8.0]
  def change
    create_table :device_baselines do |t|
      t.references :device, null: false, foreign_key: true, index: { unique: true }
      t.integer :window_minutes, null: false, default: 60
      t.bigint :p95_uplink_bytes_per_min, null: false, default: 0
      t.integer :p95_conn_count_per_min, null: false, default: 0
      t.integer :p95_new_dst_ips_per_10m, null: false, default: 0
      t.integer :p95_unique_ports_per_10m, null: false, default: 0
      t.datetime :updated_at, null: false
    end
  end
end
