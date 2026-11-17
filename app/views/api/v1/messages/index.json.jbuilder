json.messages do
  json.array! @messages do |message|
    json.partial! "api/v1/partials/message", message: message
  end
end

json.meta do
  json.before_id @before_id
  json.has_more @has_more
end
