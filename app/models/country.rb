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

  # Launch gate: a country can only go live when every legal page exists
  # and is published in its default locale (the message lists what is
  # still missing).
  validate :legal_pages_ready, on: :update, if: -> { enabled? && enabled_changed? }

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

  # Legal page slugs with no PUBLISHED page in this country's default
  # locale — empty when the country may legally launch.
  def missing_legal_slugs
    published = LegalPage.published.where(country_code: code, locale: default_locale).pluck(:slug)
    LegalPage::SLUGS - published
  end

  # Read-only launch checklist rendered on the admin countries page.
  def launch_checklist
    {
      legal_pages: missing_legal_slugs.empty?,
      categories: Category.active.exists?,
      support_email: Setting.get("support_email").to_s.match?(URI::MailTo::EMAIL_REGEXP)
    }
  end

  private

  def legal_pages_ready
    missing = missing_legal_slugs
    return if missing.empty?

    errors.add(:enabled, :missing_legal_pages, slugs: missing.join(", "))
  end
end
