class LegalPage < ApplicationRecord
  SLUGS = %w[terms privacy cookies legal_notice returns buyer_protection
             seller_terms prohibited_items].freeze

  validates :country_code, presence: true, length: { is: 2 }
  validates :locale, inclusion: { in: I18n.available_locales.map(&:to_s) }
  validates :slug, presence: true, inclusion: { in: SLUGS }
  validates :title, presence: true
  validates :body, presence: true

  scope :published, -> { where(published: true) }
  scope :for_country, ->(code) { where(country_code: code) }

  def self.find_published(country_code:, locale:, slug:)
    published.find_by(country_code: country_code, locale: locale, slug: slug)
  end

  # Public delivery fallback chain (Phase 7b): exact locale of the request,
  # then English, then the country's configured default locale. nil when
  # nothing published exists for that country at all.
  def self.find_public(country_code:, locale:, slug:)
    chain = [ locale.to_s, "en", Country.find_by(code: country_code)&.default_locale ].compact.uniq
    chain.filter_map { |loc| find_published(country_code: country_code, locale: loc, slug: slug) }.first
  end

  # Slugs with a deliverable (chain-resolved) page for this country+locale,
  # mapped to the locale the reader would actually get — drives the footer
  # legal column without N+1s per link.
  def self.deliverable_slugs(country_code:, locale:)
    chain = [ locale.to_s, "en", Country.find_by(code: country_code)&.default_locale ].compact.uniq
    ranked = {}
    published.where(country_code: country_code, locale: chain).each do |page|
      current = ranked[page.slug]
      ranked[page.slug] = page.locale if current.nil? || chain.index(page.locale) < chain.index(current)
    end
    SLUGS.filter_map { |slug| [ slug, ranked[slug] ] if ranked.key?(slug) }.to_h
  end
end
