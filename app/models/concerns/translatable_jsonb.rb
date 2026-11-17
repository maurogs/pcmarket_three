# Shared handling of the jsonb translation columns (Category.names /
# seo_descriptions, SpecAttribute.names, SpecOption.names, Label.names,
# SellerTag.names). `assign_translations` merges permitted per-locale inputs
# into the existing hash: blank values clear a locale, untouched locales are
# preserved — so editing one tab never drops the other five.
module TranslatableJsonb
  extend ActiveSupport::Concern

  def assign_translations(attribute, incoming)
    incoming = incoming.to_h
    merged = public_send(attribute).to_h.stringify_keys

    incoming.each do |locale, value|
      value = value.to_s.strip
      if value.empty?
        merged.delete(locale.to_s)
      else
        merged[locale.to_s] = value
      end
    end

    public_send("#{attribute}=", merged)
  end
end
