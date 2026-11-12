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
  end
end
