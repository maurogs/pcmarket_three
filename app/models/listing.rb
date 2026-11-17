class Listing < ApplicationRecord
  include PgSearch::Model

  class InvalidTransition < StandardError; end

  MAX_PHOTOS = 12
  MAX_PHOTO_BYTES = 10.megabytes
  PHOTO_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze
  MAX_SELLER_TAGS = 5
  POSTAL_CODE_FORMATS = { "ES" => /\A\d{5}\z/ }.freeze

  # How long an accepted offer locks the listing for its buyer
  # (ExpireOffersJob releases expired reservations back to approved).
  RESERVATION_TTL = 48.hours

  # Named variants for rendered photos: small WebP for cards/carousels,
  # wide WebP for the show-page gallery.
  PHOTO_VARIANTS = {
    card: { format: :webp, resize_to_limit: [ 400, 400 ] }.freeze,
    gallery: { format: :webp, resize_to_limit: [ 1200, 1200 ] }.freeze
  }.freeze

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
  # Set while status is `reserved`: the buyer whose offer was accepted, and
  # the moment the hold lapses.
  belongs_to :reserved_for, class_name: "User", optional: true

  has_many :favorites, dependent: :destroy
  has_many :favorited_by, through: :favorites, source: :user
  has_many :offers, dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_many :moderation_events, dependent: :destroy
  has_many :reports, dependent: :destroy
  has_many :listing_labels, dependent: :destroy
  has_many :labels, through: :listing_labels
  has_many :listing_tags, dependent: :destroy
  has_many :seller_tags, through: :listing_tags
  has_many :order_items, dependent: :nullify

  has_many_attached :photos

  # Only these category trees get a performance_score (they carry gpu/cpu
  # spec fields and are what the PC Finder queries).
  SCORABLE_CATEGORY_SLUGS = %w[gaming-pcs workstations laptops].freeze
  # The PC Finder only surfaces complete gaming PCs.
  FINDER_CATEGORY_SLUGS = %w[gaming-pcs].freeze

  # The composite score (Performance::Scorer) is recomputed whenever the
  # specs or the category move — see the service for the weighting rules.
  before_save :refresh_performance_score,
              if: -> { new_record? || will_save_change_to_specs? || will_save_change_to_category_id? }

  # A price CUT on a live listing alerts the users who saved it (at most once
  # per listing per 24h — see Listings::PriceDropNotifier) and a listing
  # that just became APPROVED fans out to saved-search matches.
  after_update_commit :alert_price_drop, if: -> { saved_change_to_price_cents? }
  after_commit :match_saved_searches, on: :update,
               if: -> { saved_change_to_status? && approved? }

  validates :title, presence: true, length: { in: 5..120 }
  validates :description, length: { maximum: 20_000 }, allow_nil: true
  validates :price_cents, presence: true,
            numericality: { only_integer: true, greater_than: 0 }
  validates :original_price_cents,
            numericality: { only_integer: true, greater_than: 0 },
            allow_nil: true
  validate :original_price_above_current_price
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :shipping_price_cents,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :currency, presence: true
  validates :country_code, presence: true
  validates :slug, presence: true, uniqueness: true
  validate :postal_code_format
  validate :region_known
  validate :specs_must_be_a_hash
  validate :validate_specs
  validate :validate_required_specs, on: :submission
  validate :seller_tags_within_limit
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
  scope :discounted, -> { where("original_price_cents IS NOT NULL AND original_price_cents > price_cents") }
  scope :in_category_slug, ->(slug) { where(category: Category.where(slug: slug)) }
  # Gaming PCs and every subcategory below them (PC Finder scope, phase 7a).
  scope :in_finder_categories, -> {
    where(category_id: Category.where(slug: FINDER_CATEGORY_SLUGS).flat_map(&:self_and_descendant_ids))
  }
  scope :recently_sold, -> { where(status: :sold).order(sold_at: :desc, id: :desc) }

  # Most recently rejected listings of one seller, for the dashboard's
  # "Needs attention" list (rejection_reason carries the admin's note).
  scope :recently_rejected_for, ->(user) {
    where(user_id: user.id, status: :rejected).order(updated_at: :desc, id: :desc)
  }

  # Listings whose `specs` jsonb carries this value for the attribute key —
  # as the scalar form (select/number/text) or as an array member
  # (multi_select). Used to block deleting an in-use spec option.
  scope :using_spec_value, ->(key, value) {
    where("specs -> ? = to_jsonb(?::text) OR (jsonb_typeof(specs -> ?) = 'array' AND specs -> ? @> to_jsonb(?::text))",
          key, value, key, key, value)
  }

  # Has at least one photo attachment (admin index filter).
  scope :with_photos, -> {
    where(id: ActiveStorage::Attachment.where(record_type: "Listing", name: "photos").select(:record_id))
  }

  # Everything a card needs in one round trip: photo attachments plus the
  # store/user/labels/category rendered on the card. Use on every relation that
  # renders cards.
  scope :with_card_data, -> {
    with_attached_photos.includes(:store, :user, :labels, :category, photos_attachments: :blob)
  }

  # Listings favorited within the window, most saved first.
  scope :most_saved_since, ->(since) {
    published
      .where(id: Favorite.where(created_at: since..).select(:listing_id))
      .order(favorites_count: :desc, published_at: :desc, id: :desc)
  }

  # Money-like decimal value built from the integer cents column.
  def price
    Money.new(price_cents, currency)
  end

  # Published listings in the same category whose price sits closest to this
  # one; used for the "Similar listings" rail on the show page.
  def self.similar_to(listing, limit: 8)
    published
      .where(category_id: listing.category_id)
      .where.not(id: listing.id)
      .order(Arel.sql(sanitize_sql_array([ "ABS(price_cents - ?) ASC", listing.price_cents ])))
      .order(published_at: :desc, id: :desc)
      .limit(limit)
  end

  # The seller's other published listings, newest first: "More from this seller".
  def self.from_seller_of(listing, limit: 8)
    published
      .where(user_id: listing.user_id)
      .where.not(id: listing.id)
      .order(published_at: :desc, id: :desc)
      .limit(limit)
  end

  # --- Admin moderation aids (Phase 6a) -------------------------------------

  # pg_trgm powers the queue's duplicate-title warning; the extension is
  # added by migration 20261118010001, but the check keeps the query safe
  # on databases where it is missing.
  def self.trgm_available?
    return @trgm_available if defined?(@trgm_available)

    @trgm_available = connection.select_value(
      "SELECT 1 FROM pg_extension WHERE extname = 'pg_trgm'"
    ) == 1
  end

  # The seller's other listings with trigram-similar titles (duplicate
  # warning on the moderation page); empty when pg_trgm is unavailable.
  def self.potential_duplicates_of(listing, threshold: 0.6, limit: 5)
    return none unless trgm_available? && listing.title.present?

    where(user_id: listing.user_id)
      .where.not(id: listing.id)
      .where("similarity(title, ?) >= ?", listing.title, threshold)
      .order(Arel.sql(sanitize_sql_array([ "similarity(title, ?) DESC", listing.title ])))
      .limit(limit)
  end

  # Median approved price in the listing's category (other listings only),
  # integer cents; nil when the category has no comparables.
  def self.category_median_price_cents(listing)
    where(category_id: listing.category_id, status: :approved)
      .where.not(id: listing.id)
      .pick(Arel.sql("percentile_cont(0.5) WITHIN GROUP (ORDER BY price_cents)"))
      &.round
  end

  # Recompute every listing's search vector. Rails' fixture inserts go through
  # bulk INSERTs that trg_listings_tsv does not fire for, so the test suite
  # calls this once fixtures are loaded.
  def self.reindex_search_vectors!
    connection.execute(<<~SQL)
      UPDATE listings SET tsv = setweight(to_tsvector('simple', coalesce(title, '')), 'A') ||
                           setweight(to_tsvector('simple', coalesce(description, '')), 'B')
    SQL
  end

  def discount_percent
    return 0 if original_price_cents.nil? || original_price_cents <= price_cents

    (((original_price_cents - price_cents).to_f / original_price_cents) * 100).round
  end

  # --- State machine (guards raise Listing::InvalidTransition) -------------

  # Drafts and rejected listings go through the normal publish flow. Approved
  # listings may re-submit after material edits (see Listings::Update), which
  # is why :approved is an allowed source here as well.
  def submit_for_review!
    ensure_transition!(from: [ :draft, :rejected ], to: :pending_review)
    raise ActiveRecord::RecordInvalid, self unless valid?(:submission)

    update!(status: :pending_review, rejection_reason: nil)
  end

  # Back to the review queue after an approved listing's material fields were
  # edited (title, description, photos, specs, category). Price and shipping
  # edits do NOT call this and leave the listing live.
  def request_revalidation!
    ensure_transition!(from: [ :approved ], to: :pending_review)
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

  # Offer accepted: hold the listing for the buyer for RESERVATION_TTL.
  def reserve_for!(buyer)
    ensure_transition!(from: [ :approved ], to: :reserved)
    update!(status: :reserved, reserved_for: buyer,
            reserved_until: Time.current + RESERVATION_TTL)
  end

  # Reservation lapsed (or the deal fell through): back to the public pool.
  def release_reservation!
    return unless reserved?

    update!(status: :approved, reserved_for: nil, reserved_until: nil)
  end

  # Can this (possibly anonymous) buyer buy the listing right now? A
  # reserved listing is purchasable only by the buyer it is reserved for.
  def purchasable_by?(user)
    approved? || (reserved? && user.present? && reserved_for_id == user.id)
  end

  # Checkout cancelled: put the reserved units back on sale. The quantity
  # goes up, so the > 0 validation can never be violated by this move.
  def add_back_quantity!(units)
    update!(quantity: quantity + units)
  end

  # Sold listing revived after the order that sold it was cancelled: back
  # into the public pool.
  def reinstate!
    ensure_transition!(from: [ :sold ], to: :approved)
    update!(status: :approved, sold_at: nil)
  end

  # Tri-state allow_offers column: nil falls back to the store default.
  def offers_allowed?
    return allow_offers unless allow_offers.nil?

    store ? store.allow_offers_default : true
  end

  def archive!
    ensure_transition!(from: [ :draft, :rejected, :approved ], to: :archived)
    update!(status: :archived)
  end

  # Destroy is only offered for listings that were never (or are no longer)
  # public: drafts, rejected and archived ones. Everything else is history.
  def destroyable?
    draft? || rejected? || archived?
  end

  # Per-tab counts for "My listings", from a single GROUP BY query:
  # {"all" => total, "draft" => n, "pending_review" => n, …} for every status.
  def self.status_counts(relation)
    raw = relation.group(:status).count
    counts = statuses.keys.index_with(0)
    raw.each do |key, value|
      name = key.is_a?(Integer) ? statuses.key(key) : key.to_s
      counts[name] = value if counts.key?(name)
    end
    counts["all"] = raw.values.sum
    counts
  end

  # Scoring applies to gaming PCs, workstations and laptops — checked
  # against the category's ancestor chain so subcategories inherit it.
  # Public: the performance:backfill task calls it per listing.
  def scorable_category?
    return false if category.nil?

    Category.where(id: category.self_and_ancestor_ids)
            .exists?(slug: SCORABLE_CATEGORY_SLUGS)
  end

  private

  def alert_price_drop
    return unless price_cents_before_last_save && price_cents < price_cents_before_last_save

    Listings::PriceDropNotifier.call(self)
  end

  def match_saved_searches
    SavedSearchMatchJob.perform_later(id)
  end

  def ensure_transition!(from:, to:)
    return if from.map(&:to_s).include?(status.to_s)

    raise InvalidTransition,
          I18n.t("listings.transition.invalid", from: self.class.human_attribute_name("status/#{status}"),
                                                 to: self.class.human_attribute_name("status/#{to}"))
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

  # Composite 0-1000 gaming score from the gpu_model/cpu_model specs
  # (Performance::Scorer). nil when no tier matches — never a fake score.
  def refresh_performance_score
    self.performance_score =
      scorable_category? ? Performance::Scorer.score_from_specs(specs) : nil
  end

  # Specs must belong to the category's attribute set (own + inherited) and
  # their values must respect the attribute's input type. select and
  # multi_select values are checked against the category's SpecOptions, so
  # stray or hand-crafted keys/values surface as validation errors.
  def validate_specs
    return if specs.blank? || category.nil?

    attributes = category.all_spec_attributes.index_by(&:key)
    specs.each do |key, value|
      attribute = attributes[key.to_s]
      if attribute.nil?
        errors.add(:specs, :spec_key_unknown, attribute: key.to_s.humanize)
        next
      end

      validate_spec_value(attribute, value)
    end
  end

  # Required spec attributes (per the category's CategorySpecAttribute rows)
  # are enforced only when submitting for review, never while saving a draft.
  def validate_required_specs
    return if category.nil? || !specs.is_a?(Hash)

    required_map = category.spec_attribute_required_map
    category.all_spec_attributes.each do |attribute|
      next unless required_map[attribute.id]

      value = specs[attribute.key]
      # A boolean false is a real answer; only nil/""/[] count as missing.
      next if !value.nil? && (value == false || value.present?)

      errors.add(:specs, :spec_required, attribute: attribute.name)
    end
  end

  def validate_spec_value(attribute, value)
    case attribute.input_type
    when "select"
      unless option_value?(attribute, value)
        errors.add(:specs, :spec_value_invalid, attribute: attribute.name)
      end
    when "multi_select"
      unless value.is_a?(Array) && value.all? { |v| option_value?(attribute, v) }
        errors.add(:specs, :spec_value_invalid, attribute: attribute.name)
      end
    when "boolean"
      unless [ true, false ].include?(value)
        errors.add(:specs, :spec_value_boolean, attribute: attribute.name)
      end
    when "number"
      unless value.to_s.match?(/\A-?\d+(?:\.\d+)?\z/)
        errors.add(:specs, :spec_value_number, attribute: attribute.name)
      end
    else # text: any string is accepted
      errors.add(:specs, :too_long, attribute: attribute.name, count: 200) if value.to_s.length > 200
    end
  end

  def option_value?(attribute, value)
    value.is_a?(String) && attribute.spec_options.any? { |option| option.value == value }
  end

  def seller_tags_within_limit
    return if seller_tags.size <= MAX_SELLER_TAGS

    errors.add(:seller_tags, :seller_tag_limit, count: MAX_SELLER_TAGS)
  end

  def original_price_above_current_price
    return if original_price_cents.nil? || price_cents.nil?
    return if original_price_cents > price_cents

    errors.add(:original_price_cents, :original_price_below_price)
  end

  def postal_code_format
    pattern = POSTAL_CODE_FORMATS[country_code.to_s]
    return if postal_code.blank? || pattern.nil? || postal_code.match?(pattern)

    errors.add(:postal_code, :invalid_postal_code)
  end

  def region_known
    return if region.blank? || EsProvince.name?(region)

    errors.add(:region, :province_unknown)
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
