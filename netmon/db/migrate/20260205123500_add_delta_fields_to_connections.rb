# frozen_string_literal: true

class AddDeltaFieldsToConnections < ActiveRecord::Migration[8.0]
  def change
    add_column :connections, :last_uplink_bytes, :bigint, null: false, default: 0
    add_column :connections, :last_downlink_bytes, :bigint, null: false, default: 0
    add_column :connections, :last_uplink_packets, :bigint, null: false, default: 0
    add_column :connections, :last_downlink_packets, :bigint, null: false, default: 0
    add_column :connections, :last_delta_at, :datetime
    add_column :connections, :anomaly_score, :integer, null: false, default: 0
    add_column :connections, :anomaly_reasons_json, :text, null: false, default: "[]"
  end
end
