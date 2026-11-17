class User < ApplicationRecord
  USERNAME_FORMAT = /\A[a-zA-Z0-9_\-]{3,30}\z/
  # E.164-ish: optional +, country code cannot start with 0, 6–15 digits total.
  PHONE_FORMAT = /\A\+?[1-9]\d{5,14}\z/

  AVATAR_MAX_BYTES = 3.megabytes
  AVATAR_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze
  AVATAR_VARIANTS = {
    thumb: { format: :webp, resize_to_fill: [ 256, 256 ] }.freeze
  }.freeze

  # E-mail channels users can switch on/off (all default ON except the
  # newsletter). Read through #wants_email?; edited on the notification
  # preferences page. Keys are stored in the jsonb column as strings.
  EMAIL_PREFERENCE_KEYS = %w[
    email_new_message email_offers email_orders
    email_price_drop email_saved_search email_newsletter
  ].freeze
  DEFAULT_EMAIL_PREFERENCES = EMAIL_PREFERENCE_KEYS.index_with { |key| key != "email_newsletter" }.freeze

  enum :role, { user: 0, admin: 1 }

  has_secure_password
  has_many :sessions, dependent: :destroy

  has_one_attached :avatar
  # GDPR data-export artifact (JSON) produced by Users::DataExportJob.
  has_one_attached :export

  has_one :store, dependent: :destroy

  has_many :listings, dependent: :destroy
  has_many :favorites, dependent: :destroy
  has_many :favorite_listings, through: :favorites, source: :listing
  has_many :saved_searches, dependent: :destroy
  has_many :orders, foreign_key: "buyer_id", inverse_of: :buyer, dependent: :destroy
  has_many :sales, class_name: "Order", foreign_key: "seller_id",
                   inverse_of: :seller, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :carts, dependent: :destroy
  has_many :addresses, dependent: :destroy
  has_many :api_tokens, dependent: :destroy
  has_many :devices, dependent: :destroy
  has_many :reviews, foreign_key: "reviewer_id", inverse_of: :reviewer, dependent: :destroy
  has_many :offers, foreign_key: "buyer_id", inverse_of: :buyer, dependent: :destroy
  has_many :conversations_as_buyer, class_name: "Conversation",
           foreign_key: "buyer_id", inverse_of: :buyer, dependent: :destroy
  has_many :conversations_as_seller, class_name: "Conversation",
           foreign_key: "seller_id", inverse_of: :seller, dependent: :destroy
  has_many :messages, foreign_key: "sender_id", inverse_of: :sender, dependent: :destroy
  has_many :following, class_name: "Follow", foreign_key: "follower_id",
           inverse_of: :follower, dependent: :destroy
  has_many :stores_followed, through: :following, source: :store
  has_many :blocks_cast, class_name: "Block", foreign_key: "blocker_id",
           inverse_of: :blocker, dependent: :destroy
  has_many :blocks_received, class_name: "Block", foreign_key: "blocked_id",
           inverse_of: :blocked, dependent: :destroy
  has_many :moderation_events, foreign_key: "admin_id", inverse_of: :admin, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  # Virtual field for the password-change form (Account::SecuritiesController):
  # keeps ActiveModel able to render errors on :current_password.
  attr_accessor :current_password
  # Phones are stored in E.164-ish form; users type spaces/dashes/parens.
  normalizes :phone, with: ->(p) { p.presence&.gsub(%r{[\s.()/\-]}, "") }
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
  validates :phone, format: { with: PHONE_FORMAT }, allow_blank: true
  validate :avatar_upload_valid

  def display_name
    return I18n.t("users.deleted_display_name") if deleted?

    store&.name.presence || username
  end

  # Anonymized GDPR account (see Users::Anonymize): the @invalid domain is the
  # marker; nothing is ever e-mailed to it.
  def deleted?
    email_address.to_s.end_with?("@invalid")
  end

  # Sparse jsonb: missing keys fall back to DEFAULT_EMAIL_PREFERENCES.
  def wants_email?(kind)
    return false if deleted?

    key = kind.to_s.start_with?("email_") ? kind.to_s : "email_#{kind}"
    return true unless EMAIL_PREFERENCE_KEYS.include?(key)

    value = notification_preferences.presence&.fetch(key, nil)
    value.nil? ? DEFAULT_EMAIL_PREFERENCES.fetch(key) : value
  end

  def email_preferences
    DEFAULT_EMAIL_PREFERENCES.merge(notification_preferences.presence || {})
  end

  # Checkboxes on the notification-preferences form read through these.
  EMAIL_PREFERENCE_KEYS.each do |key|
    define_method(key) { wants_email?(key) }
  end

  # Persists the full preference matrix ({"0"/"1"} form values) in one write.
  def update_notification_preferences(preferences)
    boolean = ActiveModel::Type::Boolean.new
    preferences = preferences.symbolize_keys
    values = EMAIL_PREFERENCE_KEYS.index_with { |key| boolean.cast(preferences.fetch(key.to_sym, false)) }
    update!(notification_preferences: values)
  end

  def banned?
    !banned_at.nil?
  end

  def ban!(reason = nil)
    update!(banned_at: Time.current, ban_reason: reason)
  end

  def unban!
    update!(banned_at: nil, ban_reason: nil)
  end

  private

  def avatar_upload_valid
    return unless avatar.attached?

    unless AVATAR_CONTENT_TYPES.include?(avatar.content_type)
      errors.add(:avatar, :avatar_content_type_invalid)
    end
    if avatar.byte_size && avatar.byte_size > AVATAR_MAX_BYTES
      errors.add(:avatar, :avatar_too_large, max: AVATAR_MAX_BYTES / 1.megabyte)
    end
  end
end
