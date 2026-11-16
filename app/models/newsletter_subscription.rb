class NewsletterSubscription < ApplicationRecord
  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :email, presence: true, uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :locale, inclusion: { in: I18n.available_locales.map(&:to_s) }

  scope :confirmed, -> { where.not(confirmed_at: nil) }

  def confirm!
    update!(confirmed_at: confirmed_at || Time.current)
  end
end
