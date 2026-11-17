class Store < ApplicationRecord
  extend FriendlyId

  # :history keeps old slugs resolvable after a rename (StoresController 301s
  # them to the current slug; see FriendlyId::Slugged#should_generate_new_friendly_id?).
  friendly_id :name, use: [ :slugged, :history ]

  IMAGE_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze
  LOGO_MAX_BYTES = 5.megabytes
  BANNER_MAX_BYTES = 8.megabytes

  # Rendered variants: square thumb for sidebar cards and the storefront logo
  # (cropped), wide display image for the storefront banner.
  LOGO_VARIANTS = {
    thumb: { format: :webp, resize_to_fill: [ 256, 256 ] }.freeze,
    card: { format: :webp, resize_to_limit: [ 400, 400 ] }.freeze
  }.freeze
  BANNER_VARIANTS = {
    display: { format: :webp, resize_to_limit: [ 1600, 400 ] }.freeze
  }.freeze

  enum :store_type, { individual: 0, business: 1 }

  belongs_to :user
  has_many :listings, dependent: :nullify
  has_many :follows, dependent: :destroy
  has_many :followers, through: :follows, source: :follower
  has_many :reviews, dependent: :nullify

  has_one_attached :logo
  has_one_attached :banner

  validates :name, presence: true, length: { in: 2..60 }, uniqueness: true
  validates :slug, presence: true, uniqueness: true
  validates :description, length: { maximum: 2000 }, allow_nil: true
  validates :vat_number, length: { maximum: 20 }, allow_nil: true
  validates :vat_number, presence: true, if: :business?
  validates_with SpanishTaxIdValidator, attributes: %i[vat_number]
  validates :rating_average, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 5 }
  validates :reviews_count, :listings_count, :sales_count, :followers_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :city, length: { maximum: 60 }, allow_nil: true
  validates :region, length: { maximum: 60 }, allow_nil: true
  validate :region_known
  validates :returns_policy, :shipping_policy, length: { maximum: 5000 }, allow_nil: true
  validates :default_shipping_cents, :free_shipping_threshold_cents,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :logo_upload_valid
  validate :banner_upload_valid

  scope :active, -> { where(vacation_mode: false) }
  scope :verified, -> { where(verified: true) }
  scope :visible, -> { where(hidden: false) }

  # FriendlyId regenerates the slug when the name changes; the previous slug
  # lands in friendly_id_slugs and keeps resolving (with a 301).
  def should_generate_new_friendly_id?
    name_changed? || super
  end

  def followed_by?(user)
    return false if user.nil?

    follows.exists?(follower_id: user.id)
  end

  # Money-like decimal values for the shipping-defaults form fields.
  def default_shipping
    Money.new(default_shipping_cents, "EUR")
  end

  def enable_vacation!
    update!(vacation_mode: true)
  end

  def disable_vacation!
    update!(vacation_mode: false)
  end

  # Recomputes rating_average/reviews_count from persisted reviews.
  # Called from Review after_create/after_destroy callbacks.
  def refresh_rating!
    rated = reviews.where(hidden_at: nil).where.not(rating: nil)
    update_columns(reviews_count: rated.count, rating_average: (rated.average(:rating) || 0).round(2))
  end

  private

  def region_known
    return if region.blank? || EsProvince.name?(region)

    errors.add(:region, :province_unknown)
  end

  def logo_upload_valid
    return unless logo.attached?

    unless IMAGE_CONTENT_TYPES.include?(logo.content_type)
      errors.add(:logo, :logo_content_type_invalid)
    end
    if logo.byte_size && logo.byte_size > LOGO_MAX_BYTES
      errors.add(:logo, :logo_too_large, max: LOGO_MAX_BYTES / 1.megabyte)
    end
  end

  def banner_upload_valid
    return unless banner.attached?

    unless IMAGE_CONTENT_TYPES.include?(banner.content_type)
      errors.add(:banner, :banner_content_type_invalid)
    end
    if banner.byte_size && banner.byte_size > BANNER_MAX_BYTES
      errors.add(:banner, :banner_too_large, max: BANNER_MAX_BYTES / 1.megabyte)
    end
  end
end
