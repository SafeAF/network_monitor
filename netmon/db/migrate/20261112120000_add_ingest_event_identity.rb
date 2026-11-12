class AddIngestEventIdentity < ActiveRecord::Migration[8.0]
  def change
    # Nullable for historical receipts. All new API writes supply an identity.
    add_column :netmon_events, :event_uid, :string
    add_column :netmon_events, :payload_digest, :string
    add_index :netmon_events, [:router_id, :event_uid], unique: true
    add_index :netmon_events, :created_at
    add_column :remote_hosts, :enrichment_requested_at, :datetime
  end
end
