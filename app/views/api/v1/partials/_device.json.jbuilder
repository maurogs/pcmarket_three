json.id device.id
json.platform device.platform
# Display-truncated per the OpenAPI contract: the raw token is only ever
# sent by the client, never echoed back in full.
json.push_token device.push_token.length > 24 ? "#{device.push_token[0, 24]}…" : device.push_token
json.created_at device.created_at.utc.iso8601
