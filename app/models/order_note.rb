# Internal admin notes on an order (never visible to buyer or seller).
class OrderNote < ApplicationRecord
  MAX_BODY_LENGTH = 2000

  belongs_to :order
  belongs_to :admin, class_name: "User"

  validates :body, presence: true, length: { maximum: MAX_BODY_LENGTH }
end
