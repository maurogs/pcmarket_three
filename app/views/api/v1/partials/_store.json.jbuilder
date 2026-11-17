json.id store.id
json.name store.name
json.slug store.slug
json.store_type store.store_type
json.verified store.verified
json.vacation_mode store.vacation_mode
json.city store.city
json.region store.region
json.description store.description
json.logo_url store_logo_json(store)
json.listings_count store.listings_count
json.sales_count store.sales_count
json.rating_average store.reviews_count.positive? ? store.rating_average.to_f : nil
json.reviews_count store.reviews_count
json.followers_count store.followers_count
json.web_url store_web_url(store)
