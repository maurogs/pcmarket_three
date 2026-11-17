json.api_tokens do
  json.array! @api_tokens do |token|
    json.id token.id
    json.name token.name
    json.created_at token.created_at.utc.iso8601
    json.last_used_at token.last_used_at&.utc&.iso8601
    json.expires_at token.expires_at&.utc&.iso8601
  end
end
