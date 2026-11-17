json.saved_searches @saved_searches do |saved_search|
  json.partial! "api/v1/partials/saved_search", saved_search: saved_search
end
