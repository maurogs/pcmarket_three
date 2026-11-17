json.stores @stores do |store|
  json.partial! "api/v1/partials/store", store: store
end
json.meta do
  json.pagination pagination_meta(@pagy)
end
