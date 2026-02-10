# frozen_string_literal: true

class CreateSuppressionRules < ActiveRecord::Migration[8.0]
  def change
    create_table :suppression_rules do |t|
      t.string :code, null: false
      t.string :kind, null: false
      t.string :value, null: false
      t.references :device, foreign_key: true
      t.string :notes
      t.timestamps
    end

    add_index :suppression_rules, [:code, :kind, :value]
    add_index :suppression_rules, [:code, :kind, :value, :device_id]
  end
end
