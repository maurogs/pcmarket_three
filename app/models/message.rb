class Message < ApplicationRecord
  MAX_BODY_LENGTH = 2000

  belongs_to :conversation
  belongs_to :sender, class_name: "User"

  validates :body, presence: true, length: { maximum: MAX_BODY_LENGTH }

  scope :unread_by, ->(user) { where(sender_id: user.id, read_at: nil) }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  after_create :touch_conversation

  private

  def touch_conversation
    conversation.update_column(:last_message_at, created_at)
  end
end
