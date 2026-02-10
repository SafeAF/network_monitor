# frozen_string_literal: true

class AddNotesAndTagToRemoteHosts < ActiveRecord::Migration[8.0]
  def change
    add_column :remote_hosts, :notes, :text
    add_column :remote_hosts, :tag, :string, null: false, default: "unknown"
    add_index :remote_hosts, :tag
  end
end
