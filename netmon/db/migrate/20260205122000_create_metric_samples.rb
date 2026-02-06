# frozen_string_literal: true

class CreateMetricSamples < ActiveRecord::Migration[8.0]
  def change
    create_table :metric_samples do |t|
      t.datetime :captured_at, null: false
      t.bigint :new_dst_ips_last_10m, null: false, default: 0
      t.bigint :unique_dports_last_10m, null: false, default: 0
      t.bigint :uplink_bytes_last_10m, null: false, default: 0
      t.bigint :baseline_p95_uplink_bytes_last_10m, null: false, default: 0
      t.bigint :new_asns_last_1h, null: false, default: 0
      t.timestamps
    end

    add_index :metric_samples, :captured_at
  end
end
