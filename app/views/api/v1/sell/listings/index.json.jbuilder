json.listings do
  # One batched spec-attribute warm for every row's category, so the
  # _category partial below hits the per-instance memo instead of running
  # its CTE chain per listing (see Category.warm_spec_attributes!).
  Category.warm_spec_attributes!(@listings.filter_map(&:category).uniq)
  json.array! @listings do |listing|
    json.partial! "api/v1/partials/listing_full", listing: listing
  end
end

json.meta do
  json.pagination pagination_meta(@pagy)
end
