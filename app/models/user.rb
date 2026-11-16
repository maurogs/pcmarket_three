class User < ApplicationRecord
  USERNAME_FORMAT = /\A[a-zA-Z0-9_\-]{3,30}\z/

  enum :role, { user: 0, admin: 1 }

  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :username, with: ->(u) { u.strip }

  validates :email_address,
            presence: true,
            uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :username,
            presence: true,
            uniqueness: true,
            format: { with: USERNAME_FORMAT }
  validates :locale, inclusion: { in: I18n.available_locales.map(&:to_s) }, allow_nil: true
end
