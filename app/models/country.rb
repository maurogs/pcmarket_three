class Country < ApplicationRecord
  DEFAULTS = [
    { code: "ES", name_key: "countries.es", currency: "EUR", default_locale: "es", enabled: true,  vat_rate: "21.00" },
    { code: "FR", name_key: "countries.fr", currency: "EUR", default_locale: "fr", enabled: false, vat_rate: "20.00" },
    { code: "GB", name_key: "countries.gb", currency: "GBP", default_locale: "en", enabled: false, vat_rate: "20.00" },
    { code: "DE", name_key: "countries.de", currency: "EUR", default_locale: "de", enabled: false, vat_rate: "19.00" },
    { code: "IT", name_key: "countries.it", currency: "EUR", default_locale: "it", enabled: false, vat_rate: "22.00" },
    { code: "PT", name_key: "countries.pt", currency: "EUR", default_locale: "pt", enabled: false, vat_rate: "23.00" }
  ].freeze

  validates :code, presence: true, uniqueness: true, format: { with: /\A[A-Z]{2}\z/ }
  validates :name_key, presence: true
  validates :currency, presence: true
  validates :default_locale, inclusion: { in: I18n.available_locales.map(&:to_s) }
  validates :vat_rate, numericality: { greater_than_or_equal_to: 0 }

  scope :enabled, -> { where(enabled: true) }

  # Idempotently creates the six launch countries. Only Spain ships enabled.
  def self.seed_defaults!
    DEFAULTS.each do |attrs|
      country = find_or_initialize_by(code: attrs[:code])
      country.update!(attrs.except(:code))
    end
    order(:code)
  end

  # Display name resolved from the i18n key (e.g. "countries.es").
  def display_name
    I18n.t(name_key, default: code)
  end
end
