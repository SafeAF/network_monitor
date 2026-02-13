# frozen_string_literal: true

class CreateSystemMinutes < ActiveRecord::Migration[8.0]
  def change
    create_table :system_minutes do |t|
      t.datetime :bucket_ts, null: false
      t.float :loadavg1
      t.bigint :disk_read_bytes, default: 0, null: false
      t.bigint :disk_write_bytes, default: 0, null: false
      t.bigint :rx_bytes, default: 0, null: false
      t.bigint :tx_bytes, default: 0, null: false
      t.timestamps
    end

    add_index :system_minutes, :bucket_ts, unique: true
  end
end
