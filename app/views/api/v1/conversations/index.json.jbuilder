json.conversations @conversations do |conversation|
  json.partial! "api/v1/partials/conversation",
                conversation: conversation,
                last_message: @last_messages[conversation.id],
                unread: @unread_counts.fetch(conversation.id, 0)
end
json.meta do
  json.pagination pagination_meta(@pagy)
end
