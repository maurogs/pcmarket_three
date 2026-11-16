class Listing < ApplicationRecord
  include PgSearch::Model

  class InvalidTransition < StandardError; end

  MAX_PHOTOS = 12
  MAX_PHOTO_BYTES = 10.megabytes
  PHOTO_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze

  extend FriendlyId

  friendly_id :slug_candidates, use: [ :slugged, :sequentially_slugged ]

  enum :condition, {
    brand_new: 0, open_box: 1, used_like_new: 2, used_good: 3, for_parts: 4
  }
  enum :status, {
    draft: 0, pending_review: 1, approved: 2, rejected: 3, sold: 4, archived: 5, reserved: 6
  }

  belongs_to :user
  belongs_to :store, optional: true, counter_cache: :listings_count
  belongs_to :category, counter_cache: :listings_count

  has_many :favorites, dependent: :destroy
  has_many :favorited_by, through: :favorites, source: :user
  has_many :offers, dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_many :moderation_events, dependent: :destroy
  has_many :listing_labels, dependent: :destroy
  has_many :labels, through: :listing_labels
  has_many :listing_tags, dependent: :destroy
  has_many :seller_tags, through: :listing_tags
  has_many :order_items, dependent: :nullify

  has_many_attached :photos

  validates :title, presence: true, length: { in: 5..120 }
  validates :description, length: { maximum: 20_000 }, allow_nil: true
  validates :price_cents, presence: true,
            numericality: { only_integer: true, greater_than: 0 }
  validates :original_price_cents,
            numericality: { only_integer: true, greater_than: 0 },
            allow_nil: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :shipping_price_cents,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :currency, presence: true
  validates :country_code, presence: true
  validates :slug, presence: true, uniqueness: true
  validate :specs_must_be_a_hash
  validate :photos_within_limit
  validate :photos_content_types_valid
  validate :photos_sizes_valid

  pg_search_scope :search_text,
                  against: [ :title, :description ],
                  using: {
                    tsearch: { tsvector_column: "tsv", dictionary: "simple" }
                  }

  scope :published, -> { where(status: :approved) }
  scope :visible, -> { where(status: [ :approved, :sold ]) }
  scope :featured, -> { where("featured_until > ?", Time.current) }
  scope :in_country, ->(code) { where(country_code: code) }
  scope :recent, -> { order(published_at: :desc, id: :desc) }

  # Money-like decimal value built from the integer cents column.
  def price
    Money.new(price_cents, currency)
  end

  def discount_percent
    return 0 if original_price_cents.nil? || original_price_cents <= price_cents

    (((original_price_cents - price_cents).to_f / original_price_cents) * 100).round
  end

  # --- State machine (guards raise Listing::InvalidTransition) -------------

  def submit_for_review!
    ensure_transition!(from: [ :draft, :rejected ], to: :pending_review)
    update!(status: :pending_review, rejection_reason: nil)
  end

  def approve!(admin)
    ensure_transition!(from: [ :pending_review, :draft ], to: :approved)
    transaction do
      update!(status: :approved, published_at: published_at || Time.current,
              rejection_reason: nil)
      moderation_events.create!(admin: admin, action: :approved)
    end
  end

  def reject!(reason, admin:)
    raise InvalidTransition, I18n.t("listings.transition.reject_reason_required") if reason.blank?

    ensure_transition!(from: [ :pending_review ], to: :rejected)
    transaction do
      update!(status: :rejected, rejection_reason: reason)
      moderation_events.create!(admin: admin, action: :rejected, note: reason)
    end
  end

  def mark_sold!
    ensure_transition!(from: [ :approved, :reserved ], to: :sold)
    update!(status: :sold, sold_at: Time.current)
  end

  private

  def ensure_transition!(from:, to:)
    return if from.map(&:to_s).include?(status.to_s)

    raise InvalidTransition,
          I18n.t("listings.transition.invalid", from: self.class.human_attribute_name("status.#{status}"),
                                                 to: self.class.human_attribute_name("status.#{to}"))
  end

  def slug_candidates
    [ :title, [ :title, :id ] ]
  end

  # An empty {} is fine (accessories and games have no specs); only reject
  # non-hash assignments — the column itself is NOT NULL with default {}.
  def specs_must_be_a_hash
    return if specs.is_a?(Hash)

    errors.add(:specs, :invalid)
  end

  def photos_within_limit
    return if photos.size <= MAX_PHOTOS

    errors.add(:photos, :photo_limit_exceeded, count: MAX_PHOTOS)
  end

  def photos_content_types_valid
    photos.each do |photo|
      next if PHOTO_CONTENT_TYPES.include?(photo.content_type)

      errors.add(:photos, :photo_content_type_invalid)
      break
    end
  end

  def photos_sizes_valid
    photos.each do |photo|
      next if photo.byte_size.nil? || photo.byte_size <= MAX_PHOTO_BYTES

      errors.add(:photos, :photo_too_large, max: MAX_PHOTO_BYTES / 1.megabyte)
      break
    end
  end
end
