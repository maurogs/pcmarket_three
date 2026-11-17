# PC Finder quiz results. Published gaming PCs that clear the required
# Performance::Scorer score of the chosen games (worst-case: the MAX of the
# per-game requirement at the chosen resolution/FPS), stay inside the budget
# band, and carry every optional seller tag picked in step 5.
#
#   PcFinder::Search.new(params, country_code: "ES", request: request).call
#
# Input params (all optional — the form works progressively enhanced):
#   games[]      game slugs from config/data/games.yml (first three win)
#   resolution   1080p | 1440p | 2160p (default 1080p)
#   fps          60 | 144 | 240 (default 60)
#   budget       under_700 | 700_1200 | 1200_2000 | over_2000 (cents bounds)
#   tags[]       SellerTag slugs (vibe / cooling / RGB filters, AND-ed)
#   page         offset page ("Load more" Turbo frame)
#
# Ordering: best VALUE first (performance_score per euro). The first record
# is therefore the "best match" the results page badges. With no games
# selected there is no score bar and value falls back to 0 (unscored listings
# sink to the bottom).
class PcFinder::Search
  PER_PAGE = 9

  # One representative machine for a game slug (used for landing-page strips).
  def self.sample_for(game_slug, country_code: "ES")
    new({ game: game_slug, resolution: "1440p", fps: "144" }, country_code: country_code).call(limit: 1).records.first
  end
  RESOLUTIONS = Performance::FpsEstimator::RESOLUTIONS
  FPS_TARGETS = %w[60 144 240].freeze
  # Euro (cent) price bands; beginless/endless cover the open ends.
  BUDGETS = {
    "under_700" => (0...70_000),
    "700_1200" => (70_000...120_000),
    "1200_2000" => (120_000...200_000),
    "over_2000" => (200_000..)
  }.freeze
  MAX_GAMES = 3
  # Seller tags offered as step-5 filters in the quiz / results chip bar.
  FILTER_TAGS = %w[whiteout blackout rgb anime minimalist competitive
                   watercooled air-cooling aio-cooling silent-build].freeze

  Result = Struct.new(:records, :pagy, :total_count, :filters, :required_score, :suggestions,
                      keyword_init: true) do
    def empty?
      records.empty?
    end
  end

  def initialize(params, country_code: "ES", request: nil, limit: PER_PAGE)
    @params = (params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params).with_indifferent_access
    @country_code = country_code
    @request = request
    @limit = limit
  end

  def call(limit: @limit)
    scope = filtered_scope
    total = scope.count
    pagy = build_pagy(total, limit)

    Result.new(
      records: with_card_includes(pagy.records(scope)),
      pagy: pagy,
      total_count: total,
      filters: normalized_filters,
      required_score: required_score,
      suggestions: total.zero? ? relaxations : []
    )
  end

  # Highest per-game requirement at the chosen resolution/FPS — the bar the
  # PC must clear to run EVERY chosen game at the target.
  def required_score
    games.filter_map do |slug|
      Performance::FpsEstimator.required_scores(slug, resolution)&.fetch(fps)
    end.max
  end

  def games
    normalized_filters[:games]
  end

  def resolution
    normalized_filters[:resolution]
  end

  def fps
    normalized_filters[:fps]
  end

  private
    def normalized_filters
      @normalized_filters ||= {
        games: (Array(@params[:games]) + Array(@params[:game])).map(&:to_s).select { |s| game_slug?(s) }.first(MAX_GAMES),
        resolution: RESOLUTIONS.include?(@params[:resolution].to_s) ? @params[:resolution].to_s : "1080p",
        fps: FPS_TARGETS.include?(@params[:fps].to_s) ? @params[:fps].to_s : "60",
        budget: BUDGETS.key?(@params[:budget].to_s) ? @params[:budget].to_s : nil,
        tags: Array(@params[:tags]).map(&:to_s).select(&:present?).uniq,
        page: @params[:page]
      }
    end

    def game_slug?(slug)
      Performance::FpsEstimator::GAMES.key?(slug)
    end

    def filtered_scope
      scope = Listing.published.in_country(@country_code).in_finder_categories

      if required_score
        scope = scope.where("listings.performance_score >= ?", required_score)
      end

      if (band = BUDGETS[normalized_filters[:budget]])
        scope = scope.where(price_cents: band)
      end

      normalized_filters[:tags].each do |slug|
        scope = scope.where(
          id: ListingTag.joins(:seller_tag).where(seller_tags: { slug: slug }).select(:listing_id)
        )
      end

      # Value = score per euro (fixed point to keep it an integer sort).
      scope.reorder(
        Arel.sql("(COALESCE(listings.performance_score, 0) * 1000000 / NULLIF(listings.price_cents, 0)) DESC"),
        id: :desc
      )
    end

    # Zero-result recovery: one-click "relax this" links, most useful first.
    def relaxations
      current = base_params
      out = []

      fps_index = FPS_TARGETS.index(normalized_filters[:fps])
      if fps_index && fps_index > 0
        out << { key: "lower_fps", params: current.merge(fps: FPS_TARGETS[fps_index - 1]) }
      end

      if normalized_filters[:budget].nil? && games.any?
        # Unscored-heavy catalogue: drop the score bar entirely is not an
        # option with games chosen, so offer the cheapest band instead.
        out << { key: "cheaper_budget", params: current.merge(budget: "under_700") }
      elsif normalized_filters[:budget] && normalized_filters[:budget] != "over_2000"
        out << { key: "raise_budget", params: current.merge(budget: next_budget) }
      end

      if normalized_filters[:tags].any?
        out << { key: "drop_tags", params: current.except(:tags) }
      end

      if games.size > 1
        out << { key: "fewer_games", params: current.merge(games: games.first(1)) }
      end

      out
    end

    def next_budget
      order = PcFinder::Search::BUDGETS.keys
      order[order.index(normalized_filters[:budget]) + 1]
    end

    def base_params
      { games: games, resolution: resolution, fps: fps, budget: normalized_filters[:budget] }.compact
    end

    def build_pagy(total, limit = @limit)
      options = { limit: limit, page: normalized_filters[:page], count: total }
      options[:request] = Pagy::Request.new(request: @request) if @request
      Pagy::Offset.new(**options)
    end

    def with_card_includes(scope)
      # Exactly the card payload ListingSearch uses (browse/search results
      # render the same partials; seller_tags is only needed by the API).
      # user: :store for the card's User#display_name store fallback.
      scope.with_attached_photos
           .includes(:store, :category, :labels, user: :store, photos_attachments: :blob)
    end
end
