json.listings @result.records do |listing|
  json.partial! "api/v1/partials/listing_card", listing: listing
end
json.meta do
  json.pagination pagination_meta(@result.pagy)
  json.facets facets_json(@result.facets)
  json.filters search_filters_json(@result.filters)
end
