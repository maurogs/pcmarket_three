module Listings
  # Admin-side edit of ANY listing: every content field plus status,
  # category, labels and featured_until. Unlike Listings::Update there is no
  # revalidation dance — the admin IS the reviewer — but a status change
  # away from a publicly visible state records an `unpublished`
  # ModerationEvent (everything else gets `edited`).
  class AdminUpdate
    Result = Struct.new(:listing, :saved?, keyword_init: true)

    # Statuses a listing can be publicly seen in.
    PUBLIC_STATUSES = %w[approved sold reserved].freeze

    def self.call(listing, raw)
      new(listing, raw).call
    end

    def initialize(listing, raw)
      @listing = listing
      @raw = raw.to_h.with_indifferent_access
    end

    def call
      previous_status = listing.status
      assign_attributes
      saved = listing.save
      record_event(previous_status) if saved && listing.status_previously_changed?
      Result.new(listing: listing, saved?: saved)
    end

    private

    attr_reader :listing, :raw

    def assign_attributes
      listing.title = raw[:title] if raw.key?(:title)
      listing.description = raw[:description] if raw.key?(:description)
      listing.condition = raw[:condition] if Listing.conditions.key?(raw[:condition].to_s)
      listing.quantity = raw[:quantity] if raw[:quantity].present?
      listing.city = raw[:city].presence if raw.key?(:city)
      listing.region = raw[:region].presence if raw.key?(:region)
      listing.postal_code = raw[:postal_code].presence if raw.key?(:postal_code)
      apply_prices
      apply_category
      apply_status
      apply_featured_until
      apply_specs
      apply_labels
    end

    def apply_prices
      [ [ :price, :price_cents ], [ :original_price, :original_price_cents ],
        [ :shipping_price, :shipping_price_cents ] ].each do |field, column|
        next unless raw.key?(field)

        cents = FormAttributes.euros_to_cents(raw[field])
        if cents == FormAttributes::INVALID
          listing.errors.add(column, :invalid_price)
        else
          listing.public_send("#{column}=", column == :price_cents ? cents : cents || 0)
        end
      end
    end

    def apply_category
      return if raw[:category_id].blank?

      category = Category.find_by(id: raw[:category_id])
      listing.errors.add(:category_id, :blank) if category.nil?
      listing.category = category if category
    end

    def apply_status
      return if raw[:status].blank? || !Listing.statuses.key?(raw[:status].to_s)

      listing.status = raw[:status]
      listing.published_at ||= Time.current if listing.approved?
    end

    def apply_featured_until
      return unless raw.key?(:featured_until)

      value = raw[:featured_until].presence
      return listing.featured_until = nil if value.nil?

      begin
        listing.featured_until = Time.zone.parse(value.to_s)
      rescue ArgumentError
        listing.errors.add(:featured_until, :invalid)
      end
    end

    # Admins edit the raw jsonb as a JSON object (their field set can differ
    # from the seller picker); model validation still checks keys/values
    # against the category.
    def apply_specs
      return unless raw.key?(:specs_json)

      json = raw[:specs_json].to_s.strip
      listing.specs = {} if json.empty?
      return if json.empty?

      parsed = JSON.parse(json)
      listing.errors.add(:specs, :specs_not_hash) unless parsed.is_a?(Hash)
      listing.specs = parsed if parsed.is_a?(Hash)
    rescue JSON::ParserError
      listing.errors.add(:specs, :invalid_json)
    end

    def apply_labels
      return unless raw.key?(:label_ids)

      listing.label_ids = Label.where(id: Array(raw[:label_ids])).pluck(:id)
    end

    def record_event(previous_status)
      action = if PUBLIC_STATUSES.include?(previous_status) && !PUBLIC_STATUSES.include?(listing.status)
                 :unpublished
      else
                 :edited
      end
      listing.moderation_events.create!(admin: Current.user, action: action)
    end
  end
end
