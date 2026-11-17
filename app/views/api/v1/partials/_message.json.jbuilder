json.id message.id
json.conversation_id message.conversation_id
json.sender_id message.sender_id
json.kind message.kind
json.body message.body
json.read !message.read_at.nil?
json.created_at message.created_at.utc.iso8601
