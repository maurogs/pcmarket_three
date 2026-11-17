json.conversation do
  json.partial! "api/v1/partials/conversation",
                conversation: @conversation,
                last_message: @conversation.messages.order(:created_at, :id).last,
                unread: 0
end
if @message
  json.message do
    json.partial! "api/v1/partials/message", message: @message
  end
end
