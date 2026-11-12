# frozen_string_literal: true

class PruneNetmonEventsJob < ApplicationJob
  queue_as :default

  def perform
    # Keep receipts beyond the maximum 30-day replay window, including clock
    # skew. Bound each run so retention cannot hold SQLite's writer for long.
    10.times do
      ids = NetmonEvent.where("created_at < ?", 35.days.ago).order(:id).limit(1000).pluck(:id)
      break if ids.empty?
      NetmonEvent.where(id: ids).delete_all
    end
  end
end
