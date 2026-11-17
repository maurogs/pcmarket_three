class AddNeedsLegalReviewToLegalPages < ActiveRecord::Migration[8.0]
  def change
    # Phase 7c: seeded legal texts are TEMPLATES until a lawyer signs them
    # off. The admin form flips this to false via "Reviewed by legal counsel";
    # seed loaders then refuse to overwrite the approved text.
    add_column :legal_pages, :needs_legal_review, :boolean, null: false, default: true
  end
end
