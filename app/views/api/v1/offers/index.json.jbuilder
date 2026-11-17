json.offers do
  json.array! @offers do |offer|
    json.partial! "api/v1/partials/offer", offer: offer
  end
end

json.meta do
  json.pagination pagination_meta(@pagy)
end
