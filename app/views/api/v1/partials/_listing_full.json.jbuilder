json.partial! "api/v1/partials/listing_card", listing: listing

json.description listing.description
json.postal_code listing.postal_code
json.specs listing.specs
json.photos listing_photos_json(listing)
json.seller_tags listing.seller_tags.map(&:slug)
if listing.category
  json.category do
    json.partial! "api/v1/partials/category", category: listing.category
  end
end
