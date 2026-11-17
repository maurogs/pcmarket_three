json.offer do
  json.partial! "api/v1/partials/offer", offer: @offer
end
json.message t("api.offers.accepted")
