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

ActiveRecord::Schema[8.1].define(version: 2026_05_18_100000) do
  create_table "region_selections", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.boolean "orphaned", default: false, null: false
    t.integer "position", default: 0, null: false
    t.string "region_name", null: false
    t.datetime "updated_at", null: false
    t.index ["region_name"], name: "index_region_selections_on_region_name", unique: true
  end

  create_table "services", force: :cascade do |t|
    t.boolean "auto_update_enabled", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "dataset_updated_at"
    t.bigint "disk_bytes", default: 0, null: false
    t.boolean "enabled", default: false, null: false
    t.text "last_error"
    t.text "last_log"
    t.datetime "last_seen_at"
    t.datetime "last_update_check_at"
    t.integer "last_update_duration_s"
    t.text "last_update_error"
    t.string "last_update_status"
    t.string "name", null: false
    t.string "phase"
    t.string "pinned_image_tag"
    t.string "profile", null: false
    t.float "progress"
    t.integer "status", default: 0, null: false
    t.string "update_schedule_cron"
    t.datetime "updated_at", null: false
    t.index ["auto_update_enabled"], name: "index_services_on_auto_update_enabled"
    t.index ["enabled"], name: "index_services_on_enabled"
    t.index ["last_update_status"], name: "index_services_on_last_update_status"
    t.index ["name"], name: "index_services_on_name", unique: true
  end

  create_table "settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key"
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["key"], name: "index_settings_on_key", unique: true
  end
end
