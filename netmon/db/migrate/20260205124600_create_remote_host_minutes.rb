# frozen_string_literal: true

class CreateRemoteHostMinutes < ActiveRecord::Migration[8.0]
  def change
    create_table :remote_host_minutes do |t|
      t.references :remote_host, null: false, foreign_key: true
      t.datetime :bucket_ts, null: false
      t.integer :conn_count, null: false, default: 0
      t.bigint :uplink_bytes, null: false, default: 0
      t.bigint :downlink_bytes, null: false, default: 0
      t.bigint :uplink_packets, null: false, default: 0
      t.bigint :downlink_packets, null: false, default: 0
      t.timestamps
    end

    add_index :remote_host_minutes, [:remote_host_id, :bucket_ts], unique: true
    add_index :remote_host_minutes, :bucket_ts
  end
end
