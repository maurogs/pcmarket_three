json.categories @categories.map { |root|
  { id: root.id, name: root.name, slug: root.slug, parent_id: nil }
} + @categories.flat_map { |root|
  root.children.map { |child| { id: child.id, name: child.name, slug: child.slug, parent_id: root.id } }
}
json.conditions Listing.conditions.keys
json.conditions_labels @condition_labels
json.sort_options_labels @sort_labels
json.carriers Order::CARRIERS
json.order_statuses Order.statuses.keys
json.flags @flags
json.pc_finder_labels @pc_finder_labels
json.web_urls do
  json.home root_url
  json.listings listings_url
  json.pc_finder pc_finder_url
  json.sign_in new_session_url
  json.sign_up new_registration_url
end
json.min_app_version do
  json.ios Setting.get("min_app_version_ios")
  json.android Setting.get("min_app_version_android")
end
