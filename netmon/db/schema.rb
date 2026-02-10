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

ActiveRecord::Schema[8.0].define(version: 2026_02_05_133500) do
  create_table "anomaly_hits", force: :cascade do |t|
    t.datetime "occurred_at", null: false
    t.integer "device_id", null: false
    t.integer "remote_host_id"
    t.string "proto"
    t.string "src_ip"
    t.string "dst_ip"
    t.integer "dst_port"
    t.integer "score"
    t.bigint "total_bytes", default: 0, null: false
    t.string "summary"
    t.text "reasons_json", default: "[]", null: false
    t.string "fingerprint"
    t.datetime "suppressed_until"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["device_id", "occurred_at"], name: "index_anomaly_hits_on_device_id_and_occurred_at"
    t.index ["device_id"], name: "index_anomaly_hits_on_device_id"
    t.index ["dst_ip", "occurred_at"], name: "index_anomaly_hits_on_dst_ip_and_occurred_at"
    t.index ["fingerprint"], name: "index_anomaly_hits_on_fingerprint"
    t.index ["occurred_at"], name: "index_anomaly_hits_on_occurred_at"
    t.index ["remote_host_id"], name: "index_anomaly_hits_on_remote_host_id"
  end

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

  create_table "device_baselines", force: :cascade do |t|
    t.integer "device_id", null: false
    t.integer "window_minutes", default: 60, null: false
    t.bigint "p95_uplink_bytes_per_min", default: 0, null: false
    t.integer "p95_conn_count_per_min", default: 0, null: false
    t.integer "p95_new_dst_ips_per_10m", default: 0, null: false
    t.integer "p95_unique_ports_per_10m", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["device_id"], name: "index_device_baselines_on_device_id", unique: true
  end

  create_table "device_minutes", force: :cascade do |t|
    t.integer "device_id", null: false
    t.datetime "bucket_ts", null: false
    t.integer "conn_count", default: 0, null: false
    t.bigint "uplink_bytes", default: 0, null: false
    t.bigint "downlink_bytes", default: 0, null: false
    t.bigint "uplink_packets", default: 0, null: false
    t.bigint "downlink_packets", default: 0, null: false
    t.integer "new_dst_ips", default: 0, null: false
    t.integer "unique_dst_ips", default: 0, null: false
    t.integer "unique_dst_ports", default: 0, null: false
    t.integer "unique_dst_asns", default: 0, null: false
    t.integer "unique_protos", default: 0, null: false
    t.integer "rare_ports", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bucket_ts"], name: "index_device_minutes_on_bucket_ts"
    t.index ["device_id", "bucket_ts"], name: "index_device_minutes_on_device_id_and_bucket_ts", unique: true
    t.index ["device_id"], name: "index_device_minutes_on_device_id"
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

  create_table "remote_host_minutes", force: :cascade do |t|
    t.integer "remote_host_id", null: false
    t.datetime "bucket_ts", null: false
    t.integer "conn_count", default: 0, null: false
    t.bigint "uplink_bytes", default: 0, null: false
    t.bigint "downlink_bytes", default: 0, null: false
    t.bigint "uplink_packets", default: 0, null: false
    t.bigint "downlink_packets", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bucket_ts"], name: "index_remote_host_minutes_on_bucket_ts"
    t.index ["remote_host_id", "bucket_ts"], name: "index_remote_host_minutes_on_remote_host_id_and_bucket_ts", unique: true
    t.index ["remote_host_id"], name: "index_remote_host_minutes_on_remote_host_id"
  end

  create_table "remote_host_ports", force: :cascade do |t|
    t.integer "remote_host_id", null: false
    t.integer "dst_port", null: false
    t.datetime "first_seen_at", null: false
    t.datetime "last_seen_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "seen_count", default: 0, null: false
    t.index ["remote_host_id", "dst_port"], name: "index_remote_host_ports_on_remote_host_id_and_dst_port", unique: true
    t.index ["remote_host_id"], name: "index_remote_host_ports_on_remote_host_id"
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

  create_table "saved_queries", force: :cascade do |t|
    t.string "name", null: false
    t.string "path", null: false
    t.text "params_json", default: "{}", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "kind", default: "hosts", null: false
    t.index ["kind"], name: "index_saved_queries_on_kind"
    t.index ["path"], name: "index_saved_queries_on_path"
  end

  add_foreign_key "anomaly_hits", "devices"
  add_foreign_key "anomaly_hits", "remote_hosts"
  add_foreign_key "device_baselines", "devices"
  add_foreign_key "device_minutes", "devices"
  add_foreign_key "remote_host_minutes", "remote_hosts"
  add_foreign_key "remote_host_ports", "remote_hosts"
end
