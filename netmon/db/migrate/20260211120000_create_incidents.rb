# frozen_string_literal: true

class CreateIncidents < ActiveRecord::Migration[8.0]
  def change
    create_table :incidents do |t|
      t.string :fingerprint, null: false
      t.integer :device_id
      t.string :dst_ip
      t.integer :dst_port
      t.string :proto
      t.string :codes_csv, null: false
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.integer :count, default: 1, null: false
      t.integer :max_score, default: 0, null: false
      t.datetime :acknowledged_at
      t.string :ack_notes
      t.timestamps
    end

    add_index :incidents, :fingerprint
    add_index :incidents, :last_seen_at
    add_index :incidents, :acknowledged_at

    add_reference :anomaly_hits, :incident, foreign_key: true
  end
end
