class CartItem < ApplicationRecord
  belongs_to :cart
  belongs_to :listing

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :listing_id, uniqueness: { scope: :cart_id }

  validate :listing_is_purchasable

  private

  def listing_is_purchasable
    errors.add(:listing, :not_purchasable) unless listing&.approved?
  end
end
