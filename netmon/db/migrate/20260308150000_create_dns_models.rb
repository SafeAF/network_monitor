# frozen_string_literal: true

class CreateDnsModels < ActiveRecord::Migration[8.0]
  def change
    create_table :dns_events do |t|
      t.string :router_id, null: false
      t.datetime :observed_at, null: false
      t.string :client_ip, null: false
      t.string :qname, null: false
      t.string :qtype, null: false
      t.string :rcode
      t.string :resolver
      t.text :answers_json, null: false, default: "[]"
      t.string :dedupe_key, null: false

      t.timestamps
    end

    add_index :dns_events, :observed_at
    add_index :dns_events, [:client_ip, :observed_at]
    add_index :dns_events, [:qname, :observed_at]
    add_index :dns_events, :dedupe_key, unique: true

    create_table :dns_event_answers do |t|
      t.references :dns_event, null: false, foreign_key: true
      t.string :answer_ip, null: false
      t.string :answer_type, null: false

      t.timestamps
    end

    add_index :dns_event_answers, [:answer_ip, :created_at]

    create_table :remote_host_domains do |t|
      t.references :remote_host, null: false, foreign_key: true
      t.string :domain, null: false
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.integer :seen_count, null: false, default: 0
      t.string :last_device_ip

      t.timestamps
    end

    add_index :remote_host_domains, [:remote_host_id, :domain], unique: true
  end
end
