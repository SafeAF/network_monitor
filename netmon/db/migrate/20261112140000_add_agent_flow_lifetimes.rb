class AddAgentFlowLifetimes < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_flow_lifetimes do |t|
      t.string :router_id, null: false
      t.string :flow_uid, null: false
      t.string :tuple_key, null: false
      t.string :legacy_key
      t.datetime :first_observed_at, null: false
      t.datetime :last_observed_at, null: false
      t.datetime :closed_at
      t.boolean :opening_seen, default: false, null: false
      %i[bytes_orig bytes_reply packets_orig packets_reply].each do |counter|
        t.bigint counter, default: 0, null: false
        t.check_constraint "#{counter} >= 0", name: "agent_flow_#{counter}_nonnegative"
      end
      t.timestamps
      t.index [:router_id, :flow_uid], unique: true
      t.index [:router_id, :legacy_key, :first_observed_at], name: "index_agent_flows_legacy_lookup"
      t.index :last_observed_at, where: "closed_at IS NOT NULL", name: "index_agent_flows_closed_retention"
    end
    add_column :connections, :agent_flow_uid, :string
    add_column :ingest_sources, :flow_collector, :string
    add_check_constraint :ingest_sources, "flow_collector IS NULL OR flow_collector IN ('agent', 'snapshot')", name: "ingest_sources_flow_collector"
  end
end
