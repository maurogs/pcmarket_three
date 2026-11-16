class Follow < ApplicationRecord
  belongs_to :follower, class_name: "User"
  belongs_to :store, counter_cache: :followers_count

  validates :store_id, uniqueness: { scope: :follower_id }
end
