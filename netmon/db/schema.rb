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

ActiveRecord::Schema[8.0].define(version: 2026_02_03_120010) do
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
    t.index ["proto", "src_ip", "src_port", "dst_ip", "dst_port"], name: "index_connections_on_5_tuple", unique: true
  end

  create_table "remote_hosts", force: :cascade do |t|
    t.string "ip", null: false
    t.datetime "first_seen_at", null: false
    t.datetime "last_seen_at", null: false
    t.index ["ip"], name: "index_remote_hosts_on_ip", unique: true
  end
end
