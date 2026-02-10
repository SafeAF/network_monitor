# frozen_string_literal: true

class CreateRemoteHostPorts < ActiveRecord::Migration[8.0]
  def change
    create_table :remote_host_ports do |t|
      t.references :remote_host, null: false, foreign_key: true
      t.integer :port, null: false
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.timestamps
    end

    add_index :remote_host_ports, [:remote_host_id, :port], unique: true
  end
end
