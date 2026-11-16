class Block < ApplicationRecord
  belongs_to :blocker, class_name: "User"
  belongs_to :blocked, class_name: "User"

  validates :blocked_id, uniqueness: { scope: :blocker_id }
  validate :not_self_block

  private

  def not_self_block
    errors.add(:blocked_id, :cannot_block_self) if blocker_id == blocked_id
  end
end
