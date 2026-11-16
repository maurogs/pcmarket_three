class Conversation < ApplicationRecord
  belongs_to :listing, optional: true
  belongs_to :buyer, class_name: "User"
  belongs_to :seller, class_name: "User"

  has_many :messages, dependent: :destroy

  validates :buyer_id, uniqueness: { scope: :listing_id }, allow_nil: true

  scope :recent, -> { order(last_message_at: :desc, id: :desc) }

  # Every thread where the user is one of the two participants. Security
  # invariant: messages, read receipts and offer decisions are only ever
  # reachable through this scope, so strangers 404 instead of guessing ids.
  scope :for_user, ->(user) {
    where("conversations.buyer_id = :id OR conversations.seller_id = :id", id: user.id)
  }

  # Threads a seller started with but never replied to (no message from the
  # seller) — the dashboard "Needs attention" count. One NOT EXISTS query.
  scope :unanswered_for_seller, ->(user) {
    where(seller_id: user.id)
      .where(<<~SQL.squish)
        NOT EXISTS (
          SELECT 1 FROM messages
          WHERE messages.conversation_id = conversations.id
            AND messages.sender_id = conversations.seller_id
        )
      SQL
  }

  # How many of this user's threads still hold unread mail from the other
  # side — one query over the whole inbox, drives the header badge. Cached
  # per user; Message's after_create_commit and the read-receipt path bust
  # the entry (see clear_unread_cache).
  def self.unread_badge_count_for(user)
    Rails.cache.fetch(unread_cache_key(user), expires_in: 1.day) do
      unread_conversation_count_for(user)
    end
  end

  def self.unread_conversation_count_for(user)
    unread = Message.where(read_at: nil)
                    .where.not(sender_id: user.id)
                    .where(conversation_id: for_user(user).select(:id))
    unread.select(:conversation_id).distinct.count
  end

  # Per-conversation unread counts for a page of the inbox in ONE grouped
  # query (avoids a COUNT per row).
  def self.unread_counts_by_conversation_for(user, conversations)
    Message.where(conversation_id: conversations.map(&:id))
           .where(read_at: nil)
           .where.not(sender_id: user.id)
           .group(:conversation_id)
           .count
  end

  def self.unread_cache_key(user)
    "unread_conversations/#{user.id}"
  end

  def self.clear_unread_cache(*users)
    users.compact.each { |user| Rails.cache.delete(unread_cache_key(user)) }
  end

  def other_party(user)
    user == buyer ? seller : buyer
  end

  def participant?(user)
    buyer_id == user.id || seller_id == user.id
  end

  def blocked_by?(user)
    blocked = other_party(user)
    Block.exists?(blocker: blocked, blocked: user) ||
      Block.exists?(blocker: user, blocked: blocked)
  end

  def unread_count_for(user)
    messages.where(read_at: nil).where.not(sender_id: user.id).count
  end

  # Read receipt: a single UPDATE flips every unread message the OTHER party
  # sent in this thread. Returns the affected row count.
  def mark_messages_read_for(user)
    messages.where(sender_id: other_party(user).id, read_at: nil)
            .update_all(read_at: Time.current)
  end
end
