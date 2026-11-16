# Listing labels and seller tags from db/seeds/data/labels.yml and
# seller_tags.yml. Upsert by slug so re-running never duplicates.
SeedLoader.load_yaml("labels").each do |slug, entry|
  label = Label.find_or_initialize_by(slug:)
  label.update!(names: SeedLoader.names_for(entry), color: entry["color"])
end

SeedLoader.load_yaml("seller_tags").each do |slug, entry|
  tag = SellerTag.find_or_initialize_by(slug:)
  tag.update!(names: SeedLoader.names_for(entry))
end
