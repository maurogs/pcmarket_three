# Shared helpers for the idempotent reference-data seed loaders under
# db/seeds/. Every YAML file lives in db/seeds/data and is keyed by a stable
# identifier (slug / key), so loaders upsert with find_or_initialize_by +
# update! and re-running `bin/rails db:seed` never duplicates rows.
module SeedLoader
  DATA_PATH = File.expand_path("../data", __dir__)
  LOCALES = %w[es en fr de it pt].freeze

  module_function

  def load_yaml(name)
    path = File.join(DATA_PATH, "#{name}.yml")
    data = YAML.load_file(path, aliases: true) # anchors define shared maps
    raise ArgumentError, "Seed data #{path} is empty" if data.blank?

    data
  end

  # Validates that a locale map covers all available locales and returns a
  # plain String-keyed hash ready for a JSONB column.
  def locale_map(map)
    picked = LOCALES.filter_map { |locale| [ locale, map[locale] ] if map[locale].present? }.to_h
    missing = LOCALES - picked.keys
    if missing.any?
      raise ArgumentError, "Seed locale map #{map.inspect} is missing #{missing.join(", ")}"
    end

    picked
  end

  # Names for a seed entry: a translated `names` map, or `display` (proper
  # nouns and technical labels read identically in every locale, so sharing
  # one string is correct here) falling back to the raw value.
  def names_for(entry, fallback = nil)
    source = entry["names"] || LOCALES.index_with { entry["display"] || fallback }
    locale_map(source)
  end
end
