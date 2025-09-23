class CreatePredictions < ActiveRecord::Migration[8.0]
  def change
    create_table :predictions do |t|
      t.references :player1, null: false, foreign_key: { to_table: :players }
      t.references :player2, null: false, foreign_key: { to_table: :players }
      t.references :predicted_winner, null: false, foreign_key: { to_table: :players }
      t.decimal :confidence
      t.datetime :prediction_date

      t.timestamps
    end
  end
end
