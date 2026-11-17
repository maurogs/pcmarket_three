class Notification < ApplicationRecord
  # Kinds the notification centre knows how to render (i18n templates under
  # notifications.kinds.*, icons under NotificationsHelper::KIND_ICONS).
  KINDS = %w[
    new_message price_drop saved_search_match listing_submitted
    listing_approved listing_rejected
    order_paid order_shipped order_delivered order_completed
    order_cancelled order_disputed order_updated order_refunded order_resolved
  ].freeze

  belongs_to :user

  validates :kind, presence: true, length: { maximum: 50 }

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }

  # Matches that have not been folded into a digest e-mail yet: created after
  # the saved search's last_notified_at (or ever, when it has none).
  scope :unsent_saved_search_matches, ->(saved_search) {
    where(kind: "saved_search_match")
      .where("payload->>'saved_search_id' = ?", saved_search.id.to_s)
      .then { |rel|
        saved_search.last_notified_at ? rel.where(created_at: saved_search.last_notified_at..) : rel
      }
  }

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

  # Header bell badge. Cached per user; busted on create (below) and by the
  # read paths (NotificationsReadsController / the notifications page).
  def self.unread_count_for(user)
    Rails.cache.fetch("users/#{user.id}/unread_notifications") { unread.where(user_id: user.id).count }
  end

  def self.clear_unread_cache(user)
    Rails.cache.delete("users/#{user.id}/unread_notifications")
  end

  def self.mark_all_as_read_for(user)
    unread.where(user_id: user.id).update_all(read_at: Time.current)
    clear_unread_cache(user)
  end

  after_create_commit :bust_unread_cache_and_broadcast

  def read?
    !read_at.nil?
  end

  def unread?
    !read?
  end

  def mark_as_read!
    update!(read_at: Time.current) unless read?
    Notification.clear_unread_cache(user)
  end

  private

  # Real-time badge: replace the header bell fragment on the user's personal
  # [user, :notifications] stream (subscribed in the layout header).
  def bust_unread_cache_and_broadcast
    Notification.clear_unread_cache(user)
    Turbo::StreamsChannel.broadcast_replace_to(
      [ user, :notifications ], target: "notifications-badge",
      partial: "shared/notifications_badge", locals: { user: user }
    )
  end
end
