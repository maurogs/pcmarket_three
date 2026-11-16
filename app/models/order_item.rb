class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :listing, optional: true

  validates :title, presence: true
  validates :price_cents, presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }

  def line_total_cents
    price_cents * quantity
  end
end
