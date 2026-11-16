class User < ApplicationRecord
  USERNAME_FORMAT = /\A[a-zA-Z0-9_\-]{3,30}\z/

  enum :role, { user: 0, admin: 1 }

  has_secure_password
  has_many :sessions, dependent: :destroy

  has_one :store, dependent: :destroy

  has_many :listings, dependent: :destroy
  has_many :favorites, dependent: :destroy
  has_many :favorite_listings, through: :favorites, source: :listing
  has_many :saved_searches, dependent: :destroy
  has_many :orders, foreign_key: "buyer_id", inverse_of: :buyer, dependent: :destroy
  has_many :sales, class_name: "Order", foreign_key: "seller_id",
                   inverse_of: :seller, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :addresses, dependent: :destroy
  has_many :api_tokens, dependent: :destroy
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

  def display_name
    store&.name.presence || username
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
end
