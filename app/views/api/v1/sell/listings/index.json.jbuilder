json.listings do
  json.array! @listings do |listing|
    json.partial! "api/v1/partials/listing_full", listing: listing
  end
end

json.meta do
  json.pagination pagination_meta(@pagy)
end
