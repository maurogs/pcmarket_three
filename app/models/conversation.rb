class Conversation < ApplicationRecord
  belongs_to :listing, optional: true
  belongs_to :buyer, class_name: "User"
  belongs_to :seller, class_name: "User"

  has_many :messages, dependent: :destroy

  validates :buyer_id, uniqueness: { scope: :listing_id }, allow_nil: true

  scope :recent, -> { order(last_message_at: :desc, id: :desc) }

  def other_party(user)
    user == buyer ? seller : buyer
  end

  def blocked_by?(user)
    blocked = other_party(user)
    Block.exists?(blocker: blocked, blocked: user) ||
      Block.exists?(blocker: user, blocked: blocked)
  end
end
