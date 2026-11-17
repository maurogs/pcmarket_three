# Sitemap generation (Phase 8a): bin/rails sitemap:refresh:no_ping, scheduled
# daily through config/recurring.yml. Files land in public/sitemaps/ (served
# statically; linked from the dynamic robots.txt). Locales are path-prefixed
# (/en/..., es at the root) and every URL carries hreflang alternates for all
# six locales.
#
# Tests point SITEMAP_PUBLIC_PATH at a temp dir and run the Interpreter
# against this file directly.

SITEMAP_LOCALES = %w[es en fr de it pt].freeze

SitemapGenerator::Sitemap.default_host = ENV.fetch("APP_URL", "http://localhost:3000")
SitemapGenerator::Sitemap.public_path = ENV["SITEMAP_PUBLIC_PATH"] || Rails.root.join("public").to_s
SitemapGenerator::Sitemap.sitemaps_path = "sitemaps"
SitemapGenerator::Sitemap.compress = true

SitemapGenerator::Sitemap.create do
  # Localized variants of a locale-less path ("/listings/x" -> all six).
  def locale_paths(path)
    SITEMAP_LOCALES.map { |locale| locale == "es" ? path : "/#{locale}#{path}" }
  end

  # hreflang alternates for one localized path, back-linked across locales.
  def locale_alternates(localized_path)
    base = localized_path.sub(%r{\A/(?:en|fr|de|it|pt)}, "")
    SITEMAP_LOCALES.map do |locale|
      { lang: locale, href: locale == "es" ? base : "/#{locale}#{base}" }
    end
  end

  def add_localized(path, **options)
    locale_paths(path).each do |localized|
      add localized, options.merge(alternate: locale_alternates(localized))
    end
  end

  add_localized "/", priority: 1.0
  add_localized "/trust-and-safety", priority: 0.9
  add_localized "/pc-finder", priority: 0.9
  PagesController::PAGE_SLUGS.each { |slug| add_localized "/pages/#{slug}", priority: 0.7 }

  published = Listing.published
  counts = published.group(:category_id).count

  Category.active.order(:id).each do |category|
    add_localized "/c/#{category.slug}",
                  lastmod: published.where(category_id: category.id).maximum(:published_at),
                  priority: counts[category.id].to_i > 0 ? 0.9 : 0.7
  end

  Listing.published.find_each do |listing|
    add_localized "/listings/#{listing.slug}", lastmod: listing.updated_at, priority: 0.8
  end

  Store.joins(:listings).where(listings: { status: "approved" }).distinct.each do |store|
    add_localized "/stores/#{store.slug}", lastmod: store.updated_at, priority: 0.7
  end

  # One URL per slug: LegalPage keeps a row per (country, locale).
  LegalPage.distinct.pluck(:slug).sort.each do |slug|
    add_localized "/legal/#{slug}", priority: 0.3
  end
end
