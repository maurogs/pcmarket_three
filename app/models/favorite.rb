class Favorite < ApplicationRecord
  belongs_to :user
  belongs_to :listing, counter_cache: :favorites_count

  validates :listing_id, uniqueness: { scope: :user_id }

  scope :with_listing_data, -> {
    includes(listing: [ :store, :user, :labels, { photos_attachments: :blob } ])
  }

  # Price-drop badge for the wishlist: the listing is cheaper than at the
  # moment it was saved.
  def price_dropped?
    price_cents_at_save.present? && listing.price_cents < price_cents_at_save
  end

  def saved_price
    Money.new(price_cents_at_save, listing.currency) if price_cents_at_save
  end
end
