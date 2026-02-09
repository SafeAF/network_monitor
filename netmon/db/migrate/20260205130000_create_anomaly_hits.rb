# frozen_string_literal: true

class CreateAnomalyHits < ActiveRecord::Migration[8.0]
  def change
    create_table :anomaly_hits do |t|
      t.datetime :occurred_at, null: false
      t.references :device, null: false, foreign_key: true
      t.references :remote_host, foreign_key: true
      t.string :proto
      t.string :src_ip
      t.string :dst_ip
      t.integer :dst_port
      t.integer :score
      t.bigint :total_bytes, null: false, default: 0
      t.string :summary
      t.text :reasons_json, null: false, default: "[]"
      t.string :fingerprint
      t.datetime :suppressed_until
      t.timestamps
    end

    add_index :anomaly_hits, :occurred_at
    add_index :anomaly_hits, [:device_id, :occurred_at]
    add_index :anomaly_hits, [:dst_ip, :occurred_at]
    add_index :anomaly_hits, :fingerprint
  end
end
