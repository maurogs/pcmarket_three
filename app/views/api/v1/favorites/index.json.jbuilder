json.favorites @favorites do |favorite|
  listing = favorite.listing
  json.favorite_id favorite.id
  if favorite.price_cents_at_save
    json.saved_price_money money_json(Money.new(favorite.price_cents_at_save, listing.currency))
    json.price_dropped listing.price_cents < favorite.price_cents_at_save
  else
    json.saved_price_money nil
    json.price_dropped false
  end
  json.listing do
    json.partial! "api/v1/partials/listing_card", listing: listing
  end
end
json.meta do
  json.pagination pagination_meta(@pagy)
end
