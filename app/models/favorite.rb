class Favorite < ApplicationRecord
  belongs_to :user
  belongs_to :listing, counter_cache: :favorites_count

  validates :listing_id, uniqueness: { scope: :user_id }
end
