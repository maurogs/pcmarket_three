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
end
