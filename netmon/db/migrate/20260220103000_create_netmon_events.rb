class CreateNetmonEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :netmon_events do |t|
      t.string :event_type, null: false
      t.datetime :ts, null: false
      t.string :router_id, null: false
      t.json :data, null: false, default: {}
      t.timestamps
    end

    add_index :netmon_events, :event_type
    add_index :netmon_events, :ts
    add_index :netmon_events, :router_id
  end
end
