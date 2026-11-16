class Store < ApplicationRecord
  extend FriendlyId

  friendly_id :name, use: :slugged

  enum :store_type, { individual: 0, business: 1 }

  belongs_to :user
  has_many :listings, dependent: :nullify
  has_many :follows, dependent: :destroy
  has_many :followers, through: :follows, source: :follower
  has_many :reviews, dependent: :nullify

  has_one_attached :logo
  has_one_attached :banner

  validates :name, presence: true, length: { maximum: 80 }
  validates :slug, presence: true, uniqueness: true
  validates :description, length: { maximum: 5000 }, allow_nil: true
  validates :vat_number, length: { maximum: 20 }, allow_nil: true
  validates :rating_average, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 5 }
  validates :reviews_count, :listings_count, :sales_count, :followers_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :active, -> { where(vacation_mode: false) }
  scope :verified, -> { where(verified: true) }

  # Recomputes rating_average/reviews_count from persisted reviews.
  # Called from Review after_create/after_destroy callbacks.
  def refresh_rating!
    rated = reviews.where.not(rating: nil)
    update_columns(reviews_count: rated.count, rating_average: (rated.average(:rating) || 0).round(2))
  end
end
