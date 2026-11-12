# frozen_string_literal: true

class AgentFlowLifetime < ApplicationRecord
  validates :router_id, :flow_uid, :tuple_key, :first_observed_at, :last_observed_at, presence: true

  def counters
    Netmon::FlowAccounting::COUNTERS.to_h { |key| [key, public_send(key)] }
  end
end
