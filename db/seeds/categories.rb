# Category tree from db/seeds/data/categories.yml. Roots first, then their
# children; upsert by slug so re-running never duplicates. `position` is
# assigned by file order among siblings. Roots carry an icon and a
# translated seo_description; children get them only when the file adds one.
seo_descriptions = lambda do |entry|
  map = entry["seo_description"]
  map.present? ? SeedLoader.locale_map(map) : {}
end

SeedLoader.load_yaml("categories").each_with_index do |(slug, entry), index|
  root = Category.find_or_initialize_by(slug:)
  root.update!(
    parent: nil,
    names: SeedLoader.names_for(entry),
    seo_descriptions: seo_descriptions.call(entry),
    icon: entry["icon"],
    position: index + 1
  )

  (entry["children"] || {}).each_with_index do |(child_slug, child_entry), child_index|
    child = Category.find_or_initialize_by(slug: child_slug)
    child.update!(
      parent: root,
      names: SeedLoader.names_for(child_entry),
      seo_descriptions: seo_descriptions.call(child_entry),
      icon: child_entry["icon"],
      position: child_index + 1
    )
  end
end
