json.id conversation.id
if conversation.listing
  json.listing do
    json.id conversation.listing.id
    json.slug conversation.listing.slug
    json.title conversation.listing.title
  end
end
json.buyer { json.id conversation.buyer.id; json.display_name conversation.buyer.display_name }
json.seller { json.id conversation.seller.id; json.display_name conversation.seller.display_name }
json.last_message_body last_message&.body
json.unread_for_me unread
json.created_at conversation.created_at.utc.iso8601
json.updated_at conversation.updated_at.utc.iso8601
