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
    # Closed lifetimes retain high-water marks beyond the replay window.
    # Open flows may be long lived and cannot safely be expired by age alone.
    10.times do
      ids = AgentFlowLifetime.where.not(closed_at: nil).where("last_observed_at < ?", 35.days.ago)
        .order(:last_observed_at).limit(1000).pluck(:id)
      break if ids.empty?
      AgentFlowLifetime.where(id: ids).delete_all
    end
  end
end
