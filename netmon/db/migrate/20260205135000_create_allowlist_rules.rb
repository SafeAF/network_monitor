# frozen_string_literal: true

class CreateAllowlistRules < ActiveRecord::Migration[8.0]
  def change
    create_table :allowlist_rules do |t|
      t.string :kind, null: false
      t.string :value, null: false
      t.references :device, foreign_key: true
      t.string :notes
      t.timestamps
    end

    add_index :allowlist_rules, [:kind, :value]
    add_index :allowlist_rules, [:kind, :value, :device_id]
  end
end
