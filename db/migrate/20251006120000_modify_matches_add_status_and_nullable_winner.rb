class ModifyMatchesAddStatusAndNullableWinner < ActiveRecord::Migration[8.0]
  def change
    change_table :matches, bulk: true do |t|
      # allow winner to be null for upcoming fixtures
      change_column_null :matches, :winner_id, true

      # add status (upcoming, finished), source of the data (espn, 365scores, sample), and external id
      t.string :status, default: 'upcoming', null: false
      t.string :source
      t.string :external_id
    end

    add_index :matches, :external_id
  end
end
