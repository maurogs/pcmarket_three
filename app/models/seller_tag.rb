class SellerTag < ApplicationRecord
  include TranslatableJsonb
  include LocalizedSlug

  has_many :listing_tags, dependent: :destroy
  has_many :listings, through: :listing_tags

  validates :slug, presence: true, uniqueness: true
  validates :names, presence: true

  # Listing counts per tag in one GROUP BY (the admin index table).
  scope :with_listing_counts, -> {
    left_joins(:listing_tags).group(:id).select("seller_tags.*, COUNT(listing_tags.id) AS listings_count")
  }

  def name
    names[I18n.locale.to_s].presence || names["en"].presence
  end
end
