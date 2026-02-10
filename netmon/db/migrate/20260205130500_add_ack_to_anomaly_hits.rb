# frozen_string_literal: true

class AddAckToAnomalyHits < ActiveRecord::Migration[8.0]
  def change
    add_column :anomaly_hits, :acknowledged_at, :datetime
    add_column :anomaly_hits, :ack_notes, :text
  end
end
