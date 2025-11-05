class AddFavoriteToPlayers < ActiveRecord::Migration[6.1]
  def change
    add_column :players, :favorite, :boolean, default: false, null: false
    add_index :players, :favorite
  end
end
