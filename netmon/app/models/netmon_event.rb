class NetmonEvent < ApplicationRecord
  validates :event_type, :ts, :router_id, presence: true
end
