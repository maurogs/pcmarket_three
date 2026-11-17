module SavedSearches
  # One approved listing vs every saved search: does it match?
  #
  # Cheap path first — SQL prefilter on category ancestry (the saved search's
  # category must be the listing's category or one of its ancestors) and a
  # Ruby price-band check — then the authoritative answer comes from running
  # ListingSearch itself scoped to this one listing (only_id), so keyword,
  # spec, condition, label and tag rules can never drift apart from the
  # public results page.
  class MatchNewListing
    def self.call(listing) = new(listing).call

    def initialize(listing)
      @listing = listing
    end

    def call
      matched = []
      candidates.each do |saved_search|
        next unless price_band_ok?(saved_search)
        next unless matches?(saved_search)

        Notification.create!(
          user: saved_search.user, kind: "saved_search_match",
          payload: {
            "listing_id" => @listing.id,
            "saved_search_id" => saved_search.id,
            "saved_search_name" => saved_search.name,
            "title" => @listing.title,
            "price_cents" => @listing.price_cents,
            "currency" => @listing.currency
          }
        )
        matched << saved_search
      end
      matched
    end

    private

    attr_reader :listing

    def candidates
      ancestor_ids = listing.category.self_and_ancestor_ids
      SavedSearch.where(category_id: [ nil, *ancestor_ids ]).to_a
    end

    def price_band_ok?(saved_search)
      min = euros_to_cents(saved_search.filters["min_price"])
      max = euros_to_cents(saved_search.filters["max_price"])
      return true if min.nil? && max.nil?

      (min.nil? || listing.price_cents >= min) && (max.nil? || listing.price_cents <= max)
    end

    def matches?(saved_search)
      ListingSearch.new(saved_search.search_params,
                        country_code: listing.country_code,
                        only_id: listing.id).match?
    end

    def euros_to_cents(value)
      return nil if value.blank?

      (BigDecimal(value.to_s) * 100).round
    rescue ArgumentError, TypeError
      nil
    end
  end
end
