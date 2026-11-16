# Spec attributes, their options, and category attachments from
# db/seeds/data/spec_attributes.yml + category_spec_attributes.yml.
# Upsert by key, by (attribute, option value) and by (category, attribute).
SeedLoader.load_yaml("spec_attributes").each_with_index do |(key, entry), index|
  next if key.start_with?("x-") # YAML anchor helper section

  attribute = SpecAttribute.find_or_initialize_by(key:)
  attribute.update!(
    names: SeedLoader.names_for(entry),
    input_type: entry.fetch("input_type"),
    group: entry["group"],
    unit: entry["unit"],
    # free-text attributes cannot be used as list filters
    filterable: entry["input_type"] != "text",
    position: index + 1
  )

  Array(entry["options"]).each_with_index do |option, option_index|
    value = option["value"].to_s
    option_record = attribute.spec_options.find_or_initialize_by(value:)
    option_record.update!(
      names: SeedLoader.names_for(option, value),
      position: option_index + 1,
      popular: option["popular"] == true
    )
  end
end

SeedLoader.load_yaml("category_spec_attributes").each do |category_slug, entry|
  category = Category.find_by!(slug: category_slug)
  required = Array(entry["required"])

  Array(entry["keys"]).each do |key|
    attribute = SpecAttribute.find_by!(key:)
    link = CategorySpecAttribute.find_or_initialize_by(category:, spec_attribute: attribute)
    link.update!(required: required.include?(key), position: attribute.position)
  end
end
