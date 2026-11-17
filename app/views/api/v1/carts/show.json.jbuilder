json.cart do
  json.items do
    json.array! @summary.items do |item|
      json.partial! "api/v1/partials/cart_item", cart_item: item.cart_item
    end
  end
  json.items_count @summary.total_quantity
  json.total_money money_json(Money.new(@summary.total_cents, "EUR"))
  json.checkout_available @summary.orderable?
end
