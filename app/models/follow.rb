class Follow < ApplicationRecord
  belongs_to :follower, class_name: "User"
  belongs_to :store, counter_cache: :followers_count

  validates :store_id, uniqueness: { scope: :follower_id }
  validate :not_own_store

  private

  def not_own_store
    errors.add(:store_id, :cannot_follow_own_store) if store&.user_id == follower_id
  end
end
