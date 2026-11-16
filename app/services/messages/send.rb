module Messages
  # The only way to write into a thread: validates the participant and the
  # block state, strips and rejects blanks, records the message, then
  # notifies the other party. E-mail is only enqueued when the recipient has
  # no unread "new_message" notification for this thread in the last 15
  # minutes, so hot conversations produce one e-mail, not one per bubble.
  # Turbo broadcasts themselves live in Message#broadcast_creation.
  class Send
    Result = Struct.new(:message, :error, keyword_init: true)

    def self.call(conversation:, sender:, body:)
      new(conversation:, sender:, body:).call
    end

    def initialize(conversation:, sender:, body:)
      @conversation = conversation
      @sender = sender
      @body = body
    end

    def call
      return Result.new(error: :not_participant) unless conversation.participant?(sender)
      return Result.new(error: :blocked) if conversation.blocked_by?(sender)

      text = body.to_s.strip
      return Result.new(error: :blank) if text.empty?
      return Result.new(error: :too_long) if text.length > Message::MAX_BODY_LENGTH

      message = conversation.messages.new(sender: sender, body: text, kind: :text)
      return Result.new(error: :invalid) unless message.save

      notify(message)
      Result.new(message: message)
    end

    private

    attr_reader :conversation, :sender, :body

    def notify(message)
      recipient = conversation.other_party(sender)
      suppressed = Notification.recent_unread_message_for?(recipient, conversation.id)

      Notification.create!(
        user: recipient, kind: "new_message",
        payload: { "conversation_id" => conversation.id }
      )

      return if suppressed

      MessageNotificationMailer.with(recipient: recipient, message: message).new_message.deliver_later
    end
  end
end
