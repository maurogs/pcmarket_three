json.dashboard do
  json.listings @listing_counts
  json.published_count @published_count
  json.sold_count @sold_count
  json.revenue_cents @stats.revenue_cents
  json.revenue_money money_json(Money.new(@stats.revenue_cents, "EUR"))
  json.orders @order_counts
  json.unread_conversations @unread_conversations
  json.offers_received @offers_received
  if @store
    json.store do
      json.partial! "api/v1/partials/store", store: @store
    end
  else
    json.store nil
  end
end
