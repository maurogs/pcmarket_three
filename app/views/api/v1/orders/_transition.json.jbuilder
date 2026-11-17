json.order do
  json.partial! "api/v1/partials/order", order: @order
end
json.message @message
