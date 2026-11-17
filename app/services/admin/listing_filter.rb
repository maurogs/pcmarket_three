module Admin
  # Builds the filtered/sorted Listing relation for the admin index (also
  # the CSV export). Whitelisted params only; unparseable price/date values
  # are ignored rather than raising.
  class ListingFilter
    SORTS = { "newest" => { created_at: :desc },
              "oldest" => { created_at: :asc },
              "price_desc" => { price_cents: :desc },
              "price_asc" => { price_cents: :asc } }.freeze

    def self.call(params)
      new(params).call
    end

    def initialize(params)
      @params = params
    end

    def call
      scope = Listing.all
      scope = scope.where(status: params[:status]) if params[:status].presence_in(Listing.statuses.keys)
      scope = scope.where(category: category) if category
      scope = scope.in_country(params[:country]) if params[:country].presence_in(enabled_countries)
      scope = scope.where(user_id: User.where(username: params[:seller]).select(:id)) if params[:seller].present?
      scope = apply_prices(scope)
      scope = apply_created_range(scope)
      scope = apply_featured(scope)
      scope = scope.with_photos if params[:has_photos] == "1"
      scope = scope.search_text(params[:q]) if params[:q].present?
      scope.order(SORTS.fetch(sort_key, SORTS["newest"]).slice(:created_at, :price_cents).merge(id: :desc))
    end

    private

    attr_reader :params

    def category
      return @category if defined?(@category)

      @category = begin
        params[:category].present? ? Category.friendly.find(params[:category]) : nil
      rescue ActiveRecord::RecordNotFound
        nil
      end
    end

    def enabled_countries
      @enabled_countries ||= Country.enabled.pluck(:code)
    end

    def apply_prices(scope)
      min = cents(:min_price)
      max = cents(:max_price)
      scope = scope.where(price_cents: min..) if min
      scope = scope.where(price_cents: ..max) if max
      scope
    end

    def cents(key)
      value = Listings::FormAttributes.euros_to_cents(params[key])
      value == Listings::FormAttributes::INVALID ? nil : value
    end

    def apply_created_range(scope)
      from = parse_date(:created_from)
      to = parse_date(:created_to)
      scope = scope.where(created_at: from.beginning_of_day..) if from
      scope = scope.where(created_at: ..to.end_of_day) if to
      scope
    end

    def parse_date(key)
      params[key].present? ? Date.parse(params[key].to_s) : nil
    rescue ArgumentError
      nil
    end

    def apply_featured(scope)
      case params[:featured]
      when "active" then scope.featured
      when "none" then scope.where("featured_until IS NULL OR featured_until <= ?", Time.current)
      else scope
      end
    end

    def sort_key
      params[:sort].presence_in(SORTS.keys) || "newest"
    end
  end
end
