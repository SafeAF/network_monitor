class BindSingleIngestRouter < ActiveRecord::Migration[8.0]
  def up
    # Preserve an existing identity even after telemetry retention removes it.
    # A mixed installation requires an explicit data audit, never an arbitrary
    # choice of which router owns the existing IP-keyed normalized records.
    routers = connection.select_values(<<~SQL)
      SELECT router_id FROM netmon_events
      UNION
      SELECT router_id FROM dns_events
      LIMIT 2
    SQL
    if routers.length > 1
      raise ActiveRecord::MigrationError, "Multiple historical routers found; audit/separate their data before enabling single-router ingestion"
    end
    if routers.any? { |router| !router.is_a?(String) || !router.match?(/\A[A-Za-z0-9][A-Za-z0-9_.:-]{0,63}\z/) }
      raise ActiveRecord::MigrationError, "Invalid historical router identity; audit existing data before enabling single-router ingestion"
    end

    create_table :ingest_sources do |t|
      t.string :router_id, null: false
      t.timestamps
      t.check_constraint "id = 1", name: "ingest_sources_singleton"
      t.check_constraint "length(router_id) BETWEEN 1 AND 64", name: "ingest_sources_router_length"
    end
    if routers.one?
      stamp = connection.quote(Time.current)
      execute "INSERT INTO ingest_sources (id, router_id, created_at, updated_at) VALUES (1, #{connection.quote(routers.first)}, #{stamp}, #{stamp})"
    end
  end

  def down
    drop_table :ingest_sources
  end
end
