class ListingTag < ApplicationRecord
  belongs_to :listing
  belongs_to :seller_tag

  validates :seller_tag_id, uniqueness: { scope: :listing_id }
end
