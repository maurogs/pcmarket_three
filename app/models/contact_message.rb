# Contact-form submissions (Phase 7b). Visitors and signed-in users fill
# the form on /pages/contact; rows land here and an e-mail copy goes to the
# support address. Admins read the inbox under admin/contact_messages.
class ContactMessage < ApplicationRecord
  NAME_MAX = 100
  SUBJECT_MAX = 200
  BODY_MAX = 5000

  validates :name, presence: true, length: { in: 2..NAME_MAX }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, length: { maximum: 254 }
  validates :subject, presence: true, length: { in: 3..SUBJECT_MAX }
  validates :body, presence: true, length: { in: 10..BODY_MAX }
  validates :locale, inclusion: { in: I18n.available_locales.map(&:to_s) }

  scope :recent, -> { order(created_at: :desc, id: :desc) }
end
