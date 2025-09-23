class CreatePlayers < ActiveRecord::Migration[8.0]
  def change
    create_table :players do |t|
      t.string :name
      t.string :country
      t.integer :rank
      t.integer :points

      t.timestamps
    end
  end
end
