json.devices do
  json.array! @devices do |device|
    json.partial! "api/v1/partials/device", device: device
  end
end
