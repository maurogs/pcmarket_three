json.orders do
  json.array! @orders do |order|
    json.partial! "api/v1/partials/order", order: order
  end
end

json.meta do
  json.pagination pagination_meta(@pagy)
end
