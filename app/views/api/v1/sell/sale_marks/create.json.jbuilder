json.listing do
  json.partial! "api/v1/partials/listing_full", listing: @listing
end
json.message t("api.sells.sale_marked")
