class ListingLabel < ApplicationRecord
  belongs_to :listing
  belongs_to :label

  validates :label_id, uniqueness: { scope: :listing_id }
end
