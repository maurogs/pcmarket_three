json.addresses do
  json.array! @addresses do |address|
    json.partial! "api/v1/partials/address", address: address
  end
end
