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

ActiveRecord::Schema[8.0].define(version: 2025_10_22_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "matches", force: :cascade do |t|
    t.bigint "player1_id", null: false
    t.bigint "player2_id", null: false
    t.bigint "winner_id"
    t.string "tournament"
    t.date "date"
    t.string "score"
    t.string "surface"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status", default: "upcoming", null: false
    t.string "source"
    t.string "external_id"
    t.index ["date"], name: "index_matches_on_date"
    t.index ["external_id"], name: "index_matches_on_external_id"
    t.index ["player1_id", "player2_id", "date"], name: "index_matches_on_p1_p2_date"
    t.index ["player1_id"], name: "index_matches_on_player1_id"
    t.index ["player2_id", "player1_id", "date"], name: "index_matches_on_p2_p1_date"
    t.index ["player2_id"], name: "index_matches_on_player2_id"
    t.index ["source", "external_id"], name: "index_matches_on_source_and_external_id", unique: true
    t.index ["winner_id"], name: "index_matches_on_winner_id"
  end

  create_table "players", force: :cascade do |t|
    t.string "name"
    t.string "country"
    t.integer "rank"
    t.integer "points"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "predictions", force: :cascade do |t|
    t.bigint "player1_id", null: false
    t.bigint "player2_id", null: false
    t.bigint "predicted_winner_id", null: false
    t.decimal "confidence"
    t.datetime "prediction_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["player1_id"], name: "index_predictions_on_player1_id"
    t.index ["player2_id"], name: "index_predictions_on_player2_id"
    t.index ["predicted_winner_id"], name: "index_predictions_on_predicted_winner_id"
  end

  add_foreign_key "matches", "players", column: "player1_id"
  add_foreign_key "matches", "players", column: "player2_id"
  add_foreign_key "matches", "players", column: "winner_id"
  add_foreign_key "predictions", "players", column: "player1_id"
  add_foreign_key "predictions", "players", column: "player2_id"
  add_foreign_key "predictions", "players", column: "predicted_winner_id"
end
