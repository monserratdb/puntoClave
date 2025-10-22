class AddIndexesToMatches < ActiveRecord::Migration[6.1]
  # When adding large indexes on a production Postgres DB prefer CONCURRENTLY to avoid long
  # exclusive locks. Using algorithm: :concurrently requires disabling the surrounding
  # transaction for the migration.
  disable_ddl_transaction!

  def change
    # Composite indexes for player pair lookups. Use :concurrently for Postgres; on other
    # adapters add_index will fall back to normal behavior.
    unless index_name_exists?(:matches, 'index_matches_on_p1_p2_date')
      add_index :matches, [:player1_id, :player2_id, :date], name: 'index_matches_on_p1_p2_date', algorithm: :concurrently
    end

    unless index_name_exists?(:matches, 'index_matches_on_p2_p1_date')
      add_index :matches, [:player2_id, :player1_id, :date], name: 'index_matches_on_p2_p1_date', algorithm: :concurrently
    end

    # Index winner and date for quick recent match queries
    unless index_exists?(:matches, :winner_id, name: 'index_matches_on_winner_id')
      add_index :matches, :winner_id, name: 'index_matches_on_winner_id', algorithm: :concurrently
    end

    unless index_exists?(:matches, :date, name: 'index_matches_on_date')
      add_index :matches, :date, name: 'index_matches_on_date', algorithm: :concurrently
    end
  end
end
