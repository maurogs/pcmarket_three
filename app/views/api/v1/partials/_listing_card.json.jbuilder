json.id listing.id
json.slug listing.slug
json.title listing.title
json.status listing.status
json.condition listing.condition
json.condition_label Listing.human_attribute_name("condition/#{listing.condition}")
json.price_money listing_money(listing, :price_cents)
json.original_price_money listing_money(listing, :original_price_cents)
json.shipping_price_money listing_money(listing, :shipping_price_cents)
json.free_shipping listing.free_shipping
json.local_pickup listing.local_pickup
json.allow_offers listing.offers_allowed?
json.city listing.city
json.region listing.region
json.quantity listing.quantity
json.labels listing.labels.map(&:name)
json.photo listing_photo_json(listing)
if listing.store
  json.store do
    json.id listing.store.id
    json.name listing.store.name
    json.slug listing.store.slug
  end
end
json.created_at listing.created_at.utc.iso8601
json.updated_at listing.updated_at.utc.iso8601
json.web_url listing_web_url(listing)
