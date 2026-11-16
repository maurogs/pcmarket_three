class Review < ApplicationRecord
  belongs_to :order
  belongs_to :reviewer, class_name: "User"
  belongs_to :store, optional: true
  belongs_to :seller, class_name: "User", optional: true

  validates :rating, presence: true,
            numericality: { only_integer: true, in: 1..5 }
  validates :order_id, uniqueness: true
  validates :body, length: { maximum: 4000 }, allow_nil: true

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  after_create :refresh_store_rating
  after_destroy :refresh_store_rating
  after_update :refresh_store_rating, if: :saved_change_to_rating?

  private

  def refresh_store_rating
    target = store || seller&.store
    target&.refresh_rating!
  end
end
