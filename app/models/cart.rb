class Cart < ApplicationRecord
  belongs_to :user, optional: true
  has_many :cart_items, dependent: :destroy
  has_many :listings, through: :cart_items

  before_validation :ensure_token, on: :create

  validates :token, presence: true, uniqueness: true

  def subtotal_cents
    cart_items.sum { |item| item.listing.price_cents * item.quantity }
  end

  def total_quantity
    cart_items.sum(:quantity)
  end

  private

  def ensure_token
    self.token ||= SecureRandom.base58(24)
  end
end
