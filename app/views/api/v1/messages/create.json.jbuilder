json.message do
  json.partial! "api/v1/partials/message", message: @message
end
