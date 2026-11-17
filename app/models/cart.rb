class Cart < ApplicationRecord
  belongs_to :user, optional: true
  has_many :cart_items, dependent: :destroy
  has_many :listings, through: :cart_items

  before_validation :ensure_token, on: :create

  validates :token, presence: true, uniqueness: true

  # The signed-in user's one and only cart.
  def self.for_user(user)
    find_or_create_by!(user: user)
  end

  # Guest carts are keyed by the token held in a signed cookie.
  def self.for_token(token)
    token.present? ? find_by(token: token) : nil
  end

  def guest?
    user_id.nil?
  end

  # Sum in SQL — the header badge runs on every page.
  def total_quantity
    cart_items.sum(:quantity)
  end

  # Subtotal of every item (stale ones included) — the checkout figures,
  # which exclude stale items and add shipping, live in Carts::Summary.
  def subtotal_cents
    cart_items.includes(:listing).sum { |item| item.listing.price_cents * item.quantity }
  end

  private

  def ensure_token
    self.token ||= SecureRandom.base58(24)
  end
end
