class Setting < ApplicationRecord
  after_commit :clear_cache

  validates :key, presence: true, uniqueness: true

  # Defaults applied by db/seeds.rb (kept here as the single source of truth).
  DEFAULTS = {
    "site_name" => "PCMarket",
    "commission_percent" => 0,
    "featured_price_cents" => 0,
    "min_offer_percent" => 50,
    "support_email" => "soporte@pcmarket.example"
  }.freeze

  # Cached lookup. Missing keys are not cached, so seeding a value takes
  # effect immediately; writes clear the entry after_commit.
  def self.get(key, default = nil)
    cached = Rails.cache.fetch(cache_key(key)) do
      find_by(key: key)&.value
    end
    cached.nil? ? default : cached
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

  def self.cache_key(key)
    "settings/#{key}"
  end

  # Public so Setting.set can bust the cache synchronously (after_commit does
  # not fire inside transactional tests).
  def clear_cache
    Rails.cache.delete(Setting.cache_key(key))
  end
end
