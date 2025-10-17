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

ActiveRecord::Schema[8.0].define(version: 2024_10_10_000002) do
  create_table "documents", force: :cascade do |t|
    t.integer "tenant_id", null: false
    t.string "title", limit: 500, null: false
    t.text "content", null: false
    t.string "content_hash", limit: 64
    t.bigint "file_size"
    t.json "metadata"
    t.datetime "indexed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["content_hash"], name: "index_documents_on_content_hash"
    t.index ["indexed_at"], name: "index_documents_on_indexed_at"
    t.index ["tenant_id", "created_at"], name: "index_documents_on_tenant_id_and_created_at"
    t.index ["tenant_id"], name: "index_documents_on_tenant_id"
  end

  create_table "tenants", force: :cascade do |t|
    t.string "name", null: false
    t.string "subdomain", null: false
    t.string "api_key_hash", null: false
    t.integer "document_quota", default: 1000000, null: false
    t.integer "rate_limit_per_minute", default: 1000, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["api_key_hash"], name: "index_tenants_on_api_key_hash", unique: true
    t.index ["subdomain"], name: "index_tenants_on_subdomain", unique: true
  end

  add_foreign_key "documents", "tenants"
end
