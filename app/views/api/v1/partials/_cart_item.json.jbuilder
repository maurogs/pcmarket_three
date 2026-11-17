json.id cart_item.id
json.quantity cart_item.quantity
listing = cart_item.listing
if listing
  json.listing do
    json.partial! "api/v1/partials/listing_card", listing: listing
  end
  json.unit_price_money money_json(Money.new(listing.price_cents, listing.currency))
  json.total_money money_json(Money.new(listing.price_cents * cart_item.quantity, listing.currency))
else
  json.listing nil
  json.unit_price_money nil
  json.total_money nil
end
