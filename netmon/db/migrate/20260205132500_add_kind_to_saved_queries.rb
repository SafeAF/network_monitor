# frozen_string_literal: true

class AddKindToSavedQueries < ActiveRecord::Migration[8.0]
  def change
    add_column :saved_queries, :kind, :string, null: false, default: "hosts"
    add_index :saved_queries, :kind
  end
end
