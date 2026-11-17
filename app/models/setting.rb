class Setting < ApplicationRecord
  after_commit :clear_cache

  validates :key, presence: true, uniqueness: true

  # Defaults applied by db/seeds.rb (kept here as the single source of truth).
  DEFAULTS = {
    "site_name" => "PCMarket",
    "commission_percent" => 0,
    "featured_price_cents" => 0,
    "min_offer_percent" => 50,
    "support_email" => "soporte@pcmarket.example",
    "min_public_stat" => 50
  }.freeze

  # Phase 7b: the company identity shown on legal pages, the footer and the
  # cookie/legal blocks. Everything is admin-editable; these keys being
  # blank is a warning (dashboard banner), never a hard block.
  LEGAL_IDENTITY_KEYS = %w[
    legal_name tax_id registered_address mercantile_registry_data
    contact_email dpo_email phone
  ].freeze

  # Every key the legal-identity hash reads, and the extra keys the public
  # footer shows. The footer batches all of them in a single query.
  IDENTITY_KEYS = %w[
    legal_name trade_name site_name tax_id registered_address
    mercantile_registry_data contact_email support_email dpo_email
    phone support_phone
  ].freeze
  FOOTER_KEYS = (IDENTITY_KEYS + %w[social_links blog_url]).freeze

  # Cached lookup. Missing keys are not cached, so seeding a value takes
  # effect immediately; writes clear the entry after_commit.
  def self.get(key, default = nil)
    cached = Rails.cache.fetch(cache_key(key)) do
      find_by(key: key)&.value
    end
    cached.nil? ? default : cached
  end

  # Batched read for pages that need many keys at once (footer, legal
  # pages): one query for every key not already in the cache, then the
  # usual hit/miss semantics per key.
  def self.get_many(keys, default: nil)
    keys = keys.map(&:to_s)
    found = Rails.cache.read_multi(*keys.map { |key| cache_key(key) })
    missing = keys.reject { |key| found.key?(cache_key(key)) }
    if missing.any?
      where(key: missing).each do |setting|
        Rails.cache.write(cache_key(setting.key), setting.value)
        found[cache_key(setting.key)] = setting.value
      end
    end
    keys.to_h { |key| [ key, found.fetch(cache_key(key), default) ] }
  end

  def self.set(key, value)
    setting = find_or_initialize_by(key: key)
    setting.value = value
    setting.save!
    setting.clear_cache # immediate; after_commit below covers other write paths
    setting
  end

  def self.seed_defaults!
    DEFAULTS.each { |key, value| set(key, value) unless exists?(key: key) }
  end

  # trade_name defaults to site_name when the admin left it blank.
  def self.trade_name
    get("trade_name").to_s.presence || get("site_name", "").to_s
  end

  # Values for the legal-page placeholders ({{legal_name}}, {{tax_id}}, …)
  # and the identity block. legal_name falls back to trade_name so pages
  # never render an empty company name. Batched so pages that render the
  # identity never pay one query per key; callers that already batched a
  # wider set of keys (the footer) pass their values in.
  def self.legal_identity(values = nil)
    v = values || get_many(IDENTITY_KEYS)
    trade = v["trade_name"].to_s.presence || v["site_name"].to_s
    {
      "legal_name" => v["legal_name"].to_s.presence || trade,
      "trade_name" => trade,
      "tax_id" => v["tax_id"].to_s,
      "registered_address" => v["registered_address"].to_s,
      "registry" => v["mercantile_registry_data"].to_s,
      "contact_email" => (v["contact_email"].presence || v["support_email"]).to_s,
      "dpo_email" => v["dpo_email"].to_s,
      "phone" => (v["phone"].presence || v["support_phone"]).to_s,
      "site_name" => v["site_name"].to_s
    }
  end

  # Drives the admin dashboard's "Legal identity incomplete" banner.
  def self.legal_identity_complete?
    get_many(LEGAL_IDENTITY_KEYS).values.all? { |value| value.to_s.present? }
  end

  def self.cache_key(key)
    "settings/#{key}"
  end

  # Public so Setting.set can bust the cache synchronously (after_commit does
  # not fire inside transactional tests).
  def clear_cache
    Rails.cache.delete(Setting.cache_key(key))
  end
end
