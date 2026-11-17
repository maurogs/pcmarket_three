json.conversation do
  json.partial! "api/v1/partials/conversation",
                conversation: @conversation,
                last_message: @messages.last,
                unread: 0
end
json.messages @messages do |message|
  json.partial! "api/v1/partials/message", message: message
end
