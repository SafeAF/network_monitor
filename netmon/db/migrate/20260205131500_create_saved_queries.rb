# frozen_string_literal: true

class CreateSavedQueries < ActiveRecord::Migration[8.0]
  def change
    create_table :saved_queries do |t|
      t.string :name, null: false
      t.string :path, null: false
      t.text :params_json, null: false, default: "{}"
      t.timestamps
    end

    add_index :saved_queries, :path
  end
end
