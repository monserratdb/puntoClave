class AddUniqueIndexOnMatchesSourceExternalId < ActiveRecord::Migration[8.0]
  def change
    # Add a unique index to help deduplicate matches from the same external source
    add_index :matches, [:source, :external_id], unique: true, name: 'index_matches_on_source_and_external_id'
  end
end
