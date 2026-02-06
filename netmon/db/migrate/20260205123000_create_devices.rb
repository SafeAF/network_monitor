# frozen_string_literal: true

class CreateDevices < ActiveRecord::Migration[8.0]
  def change
    create_table :devices do |t|
      t.string :ip, null: false
      t.string :name, null: false, default: ""
      t.string :notes
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.timestamps
    end

    add_index :devices, :ip, unique: true
  end
end
