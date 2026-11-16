class Message < ApplicationRecord
  MAX_BODY_LENGTH = 2000

  # Safety-tip patterns: contact details or off-platform payment requests
  # inside a chat. Detection is advisory only — the message stays untouched
  # and the thread renders a non-blocking banner (see MessagesController#show
  # and conversations/show).
  SAFETY_PATTERNS = [
    # Spanish mobiles (6xx/7xx, with or without +34/0034) and landlines
    /\b(?:\+|00)34[\s.\-]?[67]\d{2}[\s.\-]?\d{3}[\s.\-]?\d{3}\b/,
    /\b[67]\d{2}[\s.\-]?\d{3}[\s.\-]?\d{3}\b/,
    /\b[89]\d[\s.\-]?\d{2,3}[\s.\-]?\d{2}[\s.\-]?\d{2}\b/,
    # any international-number-shaped run
    /\b(?:\+|00)\d[\d\s.\-]{7,14}\b/,
    # e-mail addresses (URI::MailTo's regexp is anchored, so we roll our own)
    /\b[\w+\-.]+@[a-z\d\-]+(?:\.[a-z\d\-]+)*\.[a-z]{2,}\b/i,
    # off-platform payment lingo
    /\b(bizum|paypal|western\s*union|transferencia|money\s?gram|remesa)\b/i
  ].freeze

  enum :kind, { text: 0, offer: 1, system: 2 }

  belongs_to :conversation
  belongs_to :sender, class_name: "User"
  belongs_to :offer, optional: true

  validates :body, presence: true, length: { maximum: MAX_BODY_LENGTH }

  scope :unread_by, ->(user) { where(sender_id: user.id, read_at: nil) }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  after_create :touch_conversation
  after_create_commit :broadcast_creation

  def safety_flagged?
    SAFETY_PATTERNS.any? { |pattern| pattern.match?(body.to_s) }
  end

  # Real-time delivery: append the bubble to every viewer of the thread and
  # refresh the inbox row for each participant on their own [user, :inbox]
  # stream. Synchronous broadcast (the after_create_commit hook already runs
  # post-transaction).
  def broadcast_creation
    Turbo::StreamsChannel.broadcast_append_to(
      conversation, target: "messages",
      partial: "messages/message", locals: { message: self }
    )

    [ conversation.buyer, conversation.seller ].each do |user|
      Turbo::StreamsChannel.broadcast_replace_to(
        [ user, :inbox ], target: "conversation_#{conversation_id}",
        partial: "conversations/row",
        locals: { conversation: conversation, viewer: user }
      )
    end

    Conversation.clear_unread_cache(conversation.buyer, conversation.seller)
  end

  private

  def touch_conversation
    conversation.update_column(:last_message_at, created_at)
  end
end
