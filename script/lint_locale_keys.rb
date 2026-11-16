#!/usr/bin/env ruby
# Compares the key trees of config/locales/{es,en,fr,de,it,pt}.yml.
# The top-level locale key is stripped; the remaining trees must be identical.
# Run with: ruby script/lint_locale_keys.rb
require "yaml"

LOCALES = %w[es en fr de it pt].freeze

def flatten_keys(node, prefix = nil)
  case node
  when Hash
    node.flat_map do |key, value|
      path = prefix ? "#{prefix}.#{key}" : key.to_s
      value.is_a?(Hash) ? flatten_keys(value, path) : [ path ]
    end
  else
    [ prefix ]
  end
end

failed = false
trees = {}

LOCALES.each do |locale|
  path = File.join(__dir__, "..", "config", "locales", "#{locale}.yml")
  data = YAML.load_file(path, permitted_classes: [ Symbol ])
  root = data.fetch(locale)
  trees[locale] = flatten_keys(root).tap(&:sort!)
end

reference = trees["es"]

trees.each do |locale, keys|
  missing = reference - keys
  extra = keys - reference
  if missing.any? || extra.any?
    failed = true
    puts "#{locale}.yml differs from es.yml:"
    puts "  missing: #{missing.inspect}" if missing.any?
    puts "  extra:   #{extra.inspect}" if extra.any?
  end
end

if failed
  exit 1
else
  puts "All #{LOCALES.size} locale files share the same #{reference.size} keys."
end
