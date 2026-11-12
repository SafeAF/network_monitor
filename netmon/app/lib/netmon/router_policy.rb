# frozen_string_literal: true

module Netmon
  module RouterPolicy
    ID_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9_.:-]{0,63}\z/
    class Unavailable < StandardError; end
    class Mismatch < EventContract::Invalid; end

    def self.authorize!(router_id, bound_router_id: nil, env: ENV)
      configured = env.fetch("NETMON_ROUTER_ID", "")
      unless configured.is_a?(String) && ID_PATTERN.match?(configured)
        raise Unavailable, "router_not_configured"
      end
      if bound_router_id && bound_router_id != configured
        raise Unavailable, "router_binding_conflict"
      end
      raise Mismatch, "router_mismatch" unless router_id == configured

      configured
    end
  end
end
