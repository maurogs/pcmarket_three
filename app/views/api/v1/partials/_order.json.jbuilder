json.id order.id
json.number order.number
json.status order.status
json.payment_provider order.payment_provider
json.buyer { json.id order.buyer.id; json.display_name order.buyer.display_name }
json.seller { json.id order.seller.id; json.display_name order.seller.display_name }
# Built outside json.items: a `do ... end` block binds to json.items and emits
# empty objects instead of these line-item hashes.
items = order.order_items.map do |item|
  {
    id: item.id,
    listing_id: item.listing_id,
    title: item.title,
    quantity: item.quantity,
    unit_price_money: money_json(Money.new(item.price_cents, order.currency)),
    total_money: money_json(Money.new(item.price_cents * item.quantity, order.currency))
  }
end

json.items items
json.subtotal_money money_json(Money.new(order.subtotal_cents, order.currency))
json.shipping_money money_json(Money.new(order.shipping_cents, order.currency))
json.total_money money_json(Money.new(order.total_cents, order.currency))
json.shipping_address order.shipping_address
json.carrier order.carrier
json.tracking_number order.tracking_number
json.paid_at order.paid_at&.utc&.iso8601
json.shipped_at order.shipped_at&.utc&.iso8601
json.delivered_at order.delivered_at&.utc&.iso8601
json.completed_at order.completed_at&.utc&.iso8601
json.cancelled_at order.cancelled_at&.utc&.iso8601
json.created_at order.created_at.utc.iso8601
json.updated_at order.updated_at.utc.iso8601
