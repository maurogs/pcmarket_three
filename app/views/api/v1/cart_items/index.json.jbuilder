json.cart_items do
  json.array! @cart_items do |cart_item|
    json.partial! "api/v1/partials/cart_item", cart_item: cart_item
  end
end
