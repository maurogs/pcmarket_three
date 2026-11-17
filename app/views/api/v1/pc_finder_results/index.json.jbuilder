json.listings @result.records do |listing|
  json.partial! "api/v1/partials/listing_card", listing: listing
end
json.meta do
  json.pagination pagination_meta(@result.pagy)
  json.required_score @result.required_score
  json.filters @result.filters
end
