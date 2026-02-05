# frozen_string_literal: true

class CreateRemoteHosts < ActiveRecord::Migration[8.0]
  def change
    create_table :remote_hosts do |t|
      t.string :ip, null: false
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
    end

    add_index :remote_hosts, :ip, unique: true
  end
end
