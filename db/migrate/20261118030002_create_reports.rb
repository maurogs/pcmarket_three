class CreateReports < ActiveRecord::Migration[8.0]
  def change
    create_table :reports do |t|
      t.references :listing, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :reason, null: false
      t.text :details
      # A report is "open" while resolved_at IS NULL. resolved_action records
      # how moderation closed it (resolved = acted on, dismissed = no action).
      t.integer :resolved_action
      t.datetime :resolved_at
      t.references :resolved_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    # One OPEN report per user per listing (a closed one frees the slot).
    add_index :reports, %i[listing_id user_id], unique: true, where: "resolved_at IS NULL"
    add_index :reports, :resolved_at
  end
end
