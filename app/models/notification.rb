class Notification < ApplicationRecord
  belongs_to :user

  validates :kind, presence: true, length: { maximum: 50 }

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }

  # True when the user already has an unread "new_message" notification for
  # this thread created inside the window — Messages::Send uses it to
  # suppress e-mail spam while a conversation is hot.
  def self.recent_unread_message_for?(user, conversation_id, within: 15.minutes)
    unread
      .where(user_id: user.id, kind: "new_message")
      .where("payload->>'conversation_id' = ?", conversation_id.to_s)
      .where(created_at: within.ago..)
      .exists?
  end

  def read?
    !read_at.nil?
  end

  def mark_as_read!
    update!(read_at: Time.current) unless read?
  end
end
