# frozen_string_literal: true

class AddAlertableToAnomalyHits < ActiveRecord::Migration[8.0]
  def change
    add_column :anomaly_hits, :alertable, :boolean, null: false, default: false
    add_index :anomaly_hits, :alertable
  end
end
