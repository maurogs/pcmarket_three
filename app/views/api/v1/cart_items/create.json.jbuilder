json.cart_item do
  json.partial! "api/v1/partials/cart_item", cart_item: @cart_item
end
json.message t("api.cart_items.added")
