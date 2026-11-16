class Offer < ApplicationRecord
  enum :status, { pending: 0, accepted: 1, declined: 2, withdrawn: 3, expired: 4 }

  belongs_to :listing
  belongs_to :buyer, class_name: "User"

  validates :amount_cents, presence: true,
            numericality: { only_integer: true, greater_than: 0 }

  scope :active, -> { where(status: :pending) }
  scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

  # Pending, unexpired offers on one seller's listings (dashboard
  # "Needs attention").
  scope :pending_for_seller, ->(user) {
    joins(:listing)
      .where(listings: { user_id: user.id })
      .active
      .not_expired
  }

  # Time-based expiry (distinct from the `expired` status enum value).
  def time_expired?
    !expires_at.nil? && expires_at <= Time.current
  end

  def price
    Money.new(amount_cents, listing.currency)
  end
end
