# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_02_05_123500) do
  create_table "connections", force: :cascade do |t|
    t.string "proto", null: false
    t.string "src_ip", null: false
    t.integer "src_port"
    t.string "dst_ip", null: false
    t.integer "dst_port"
    t.string "state"
    t.string "flags"
    t.bigint "uplink_packets", default: 0, null: false
    t.bigint "uplink_bytes", default: 0, null: false
    t.bigint "downlink_packets", default: 0, null: false
    t.bigint "downlink_bytes", default: 0, null: false
    t.datetime "first_seen_at", null: false
    t.datetime "last_seen_at", null: false
    t.bigint "last_uplink_bytes", default: 0, null: false
    t.bigint "last_downlink_bytes", default: 0, null: false
    t.bigint "last_uplink_packets", default: 0, null: false
    t.bigint "last_downlink_packets", default: 0, null: false
    t.datetime "last_delta_at"
    t.integer "anomaly_score", default: 0, null: false
    t.text "anomaly_reasons_json", default: "[]", null: false
    t.index ["proto", "src_ip", "src_port", "dst_ip", "dst_port"], name: "index_connections_on_5_tuple", unique: true
  end

  create_table "devices", force: :cascade do |t|
    t.string "ip", null: false
    t.string "name", default: "", null: false
    t.string "notes"
    t.datetime "first_seen_at", null: false
    t.datetime "last_seen_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ip"], name: "index_devices_on_ip", unique: true
  end

  create_table "metric_samples", force: :cascade do |t|
    t.datetime "captured_at", null: false
    t.bigint "new_dst_ips_last_10m", default: 0, null: false
    t.bigint "unique_dports_last_10m", default: 0, null: false
    t.bigint "uplink_bytes_last_10m", default: 0, null: false
    t.bigint "baseline_p95_uplink_bytes_last_10m", default: 0, null: false
    t.bigint "new_asns_last_1h", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["captured_at"], name: "index_metric_samples_on_captured_at"
  end

  create_table "remote_hosts", force: :cascade do |t|
    t.string "ip", null: false
    t.datetime "first_seen_at", null: false
    t.datetime "last_seen_at", null: false
    t.string "rdns_name"
    t.string "whois_name"
    t.datetime "rdns_checked_at"
    t.datetime "whois_checked_at"
    t.string "whois_asn"
    t.index ["ip"], name: "index_remote_hosts_on_ip", unique: true
  end
end
