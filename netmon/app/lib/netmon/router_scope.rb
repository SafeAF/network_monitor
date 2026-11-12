# frozen_string_literal: true

module Netmon
  module RouterScope
    def self.authorize!(router_id)
      RouterPolicy.authorize!(router_id, bound_router_id: IngestSource.find_by(id: 1)&.router_id)
    end

    def self.bind!(router_id)
      authorize!(router_id)
      source = IngestSource.find_by(id: 1) ||
        IngestSource.create_or_find_by!(id: 1) { |row| row.router_id = router_id }
      RouterPolicy.authorize!(router_id, bound_router_id: source.router_id)
    end

    def self.bind_flow_collector!(router_id, collector)
      raise ArgumentError, "invalid flow collector" unless %w[agent snapshot].include?(collector)

      IngestSource.transaction do
        bind!(router_id)
        # Obtain a write lock before the read, including on SQLite where
        # SELECT FOR UPDATE does not serialize competing claims.
        IngestSource.where(id: 1).update_all("updated_at = updated_at")
        source = IngestSource.find(1)
        if source.flow_collector && source.flow_collector != collector
          raise RouterPolicy::Unavailable, "flow_collector_conflict"
        end
        source.update!(flow_collector: collector) unless source.flow_collector
      end
    end
  end
end
