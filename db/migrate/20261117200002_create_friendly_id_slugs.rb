class CreateFriendlyIdSlugs < ActiveRecord::Migration[8.1]
  def change
    # Standard FriendlyId :history table (column names are spelled "sluggable"
    # upstream). Stores keep serving old URLs after a rename: 301-redirected to
    # the current slug by StoresController#show.
    create_table :friendly_id_slugs do |t|
      t.string :slug, null: false
      t.integer :sluggable_id, null: false
      t.string :sluggable_type, limit: 50
      t.string :scope
      t.datetime :created_at
    end

    add_index :friendly_id_slugs, [ :sluggable_type, :sluggable_id ]
    add_index :friendly_id_slugs, [ :slug, :sluggable_type ]
    add_index :friendly_id_slugs, [ :slug, :sluggable_type, :sluggable_id ], unique: true
    add_index :friendly_id_slugs, :sluggable_id
  end
end
