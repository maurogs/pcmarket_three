class SavedSearch < ApplicationRecord
  MAX_PER_USER = 25

  # Keys persisted in `filters` — the ListingSearch input params minus q
  # (which lives in its own column).
  FILTER_KEYS = %w[category min_price max_price condition f labels tags seller].freeze

  belongs_to :user
  belongs_to :category, optional: true

  # Email alerts are opt-in per search: new rows start unchecked even though
  # the DB column (Phase 1) defaults to true.
  attribute :email_alerts, default: false

  validates :name, presence: true, length: { maximum: 100 }
  validates :query, length: { maximum: 200 }, allow_nil: true
  validate :within_user_limit, on: :create

  scope :with_alerts, -> { where(email_alerts: true) }

  # Rebuild the ListingSearch input params from the stored criteria so the
  # "Run search" link and SavedSearches::MatchNewListing both drive the exact
  # same service the results page uses.
  def search_params
    { "q" => query, "category" => category&.slug }.merge(filters || {})
  end

  def self.new_from_search(user:, name:, search_filters:)
    search_filters = search_filters.to_h.with_indifferent_access
    category = Category.find_by(slug: search_filters[:category]) if search_filters[:category].present?

    new(
      user: user,
      name: name,
      query: search_filters[:q].presence,
      category: category,
      filters: FILTER_KEYS.filter_map { |key| [ key, search_filters[key] ] if search_filters[key].presence }.to_h
    )
  end

  private

  def within_user_limit
    return if user.nil?

    errors.add(:base, :saved_search_limit, count: MAX_PER_USER) if user.saved_searches.count >= MAX_PER_USER
  end
end
