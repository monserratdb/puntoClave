class CreateMatches < ActiveRecord::Migration[8.0]
  def change
    create_table :matches do |t|
      t.references :player1, null: false, foreign_key: { to_table: :players }
      t.references :player2, null: false, foreign_key: { to_table: :players }
      t.references :winner, null: false, foreign_key: { to_table: :players }
      t.string :tournament
      t.date :date
      t.string :score
      t.string :surface

      t.timestamps
    end
  end
end
