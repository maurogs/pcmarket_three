# Public listing search used by /listings, /search, /c/:slug and the store
# Listings tab. Keeps every query out of the controllers: filtering, sorting,
# pagination and one facet-count query per request all live here.
#
#   ListingSearch.new(params, country_code: "ES", request: request).call
#
# Input params (all optional):
#   q            free-text query (pg_search tsvector)
#   category     category slug; matches that category AND all descendants
#   min_price    euros (decimal string) -> compared against price_cents
#   max_price    euros -> cents
#   condition[]  Listing.conditions keys
#   f[attr][]    spec-option filters; OR-ed inside one attribute,
#                AND-ed across attributes; matches scalar AND array jsonb values
#   labels[]     Label slugs
#   tags[]       SellerTag slugs
#   seller       Store slug
#   sort         best_match | newest | price_asc | price_desc | most_favorited
#   page         offset page
class ListingSearch
  PER_PAGE = 24
  SORTS = %w[best_match newest price_asc price_desc most_favorited].freeze

  # Facet keys that come from listing columns rather than the specs jsonb.
  COLUMN_FACETS = %w[condition label seller_tag].freeze

  Result = Struct.new(:records, :pagy, :total_count, :facets, :facet_attributes, :filters,
                      keyword_init: true) do
    def empty?
      records.empty?
    end

    # Option count for one facet key. Condition values are stored as enum
    # integers, so the lookup translates the enum key first.
    def facet_count(key, value)
      if key.to_s == "condition"
        ordinal = Listing.conditions[value.to_s]
        ordinal.nil? ? 0 : facets.dig("condition", ordinal.to_s).to_i
      else
        facets.dig(key.to_s, value.to_s).to_i
      end
    end

    # Spec facets (the jsonb ones), keyed by attribute key.
    def spec_facets
      facets.except(*COLUMN_FACETS)
    end

    def applied_filters?
      filters[:q].present? || filters[:category] || filters[:min_cents] ||
        filters[:max_cents] || filters[:conditions].any? || filters[:specs].any? ||
        filters[:labels].any? || filters[:tags].any? || filters[:seller]
    end
  end

  def initialize(params, country_code: "ES", request: nil, limit: PER_PAGE)
    @params = (params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params).with_indifferent_access
    @country_code = country_code
    @request = request
    @limit = limit
  end

  def call
    scope = filtered_scope
    total = scope.count
    pagy = build_pagy(total)
    facets = facet_counts(scope)

    Result.new(
      records: pagy.records(with_card_includes(apply_sort(scope))),
      pagy: pagy,
      total_count: total,
      facets: facets,
      facet_attributes: facet_attributes_for(facets),
      filters: normalized_filters
    )
  end

  private

  # --- filtering -------------------------------------------------------------

  def filtered_scope
    scope = Listing.published.in_country(@country_code)
    # A category param that resolves to nothing must match nothing, not
    # silently drop the filter and show the whole catalogue.
    return scope.none if @params[:category].present? && category.nil?
    scope = scope.search_text(@params[:q]) if @params[:q].present?
    scope = scope.where(category_id: category.self_and_descendant_ids) if category
    scope = apply_price(scope)
    scope = apply_conditions(scope)
    scope = apply_spec_filters(scope)
    scope = apply_labels(scope)
    scope = apply_tags(scope)
    scope = scope.where(store: seller) if seller
    scope
  end

  def category
    return nil if @params[:category].blank?

    @category ||= Category.find_by(slug: @params[:category])
  end

  def seller
    return nil if @params[:seller].blank?

    @seller ||= Store.find_by(slug: @params[:seller])
  end

  def apply_price(scope)
    min = euros_to_cents(@params[:min_price])
    max = euros_to_cents(@params[:max_price])
    scope = scope.where(price_cents: min..) if min
    scope = scope.where(price_cents: ..max) if max
    scope
  end

  def apply_conditions(scope)
    values = Array(@params[:condition]).map(&:to_s) & Listing.conditions.keys
    values.any? ? scope.where(condition: values) : scope
  end

  # jsonb containment. Inside one attribute the options are OR-ed; across
  # attributes the groups are AND-ed. Values stored as arrays (multi-select
  # specs) are matched with the array containment form too.
  def apply_spec_filters(scope)
    specs.each.each do |key, values|
      attribute = filterable_attributes_by_key[key]
      next if attribute.nil? || values.empty?

      clauses = values.map do |value|
        scalar = attribute.spec_json_scalar(value)
        [ { key => scalar }.to_json, { key => [ scalar ] }.to_json ].map do |json|
          "specs @> #{Listing.connection.quote(json)}::jsonb"
        end
      end.flatten

      scope = scope.where("(#{clauses.join(" OR ")})")
    end
    scope
  end

  def apply_labels(scope)
    ids = label_rows.map(&:first)
    ids.any? ? scope.where(id: ListingLabel.where(label_id: ids).select(:listing_id)) : scope
  end

  def apply_tags(scope)
    ids = tag_rows.map(&:first)
    ids.any? ? scope.where(id: ListingTag.where(seller_tag_id: ids).select(:listing_id)) : scope
  end

  # --- sorting ---------------------------------------------------------------

  def sort
    SORTS.include?(@params[:sort].to_s) ? @params[:sort].to_s : "best_match"
  end

  def apply_sort(scope)
    columns = sort_columns
    # Featured listings first while the flag is on.
    if Flipper.enabled?(:featured_listings)
      featured = "(listings.featured_until IS NOT NULL AND listings.featured_until > NOW()) DESC"
      scope.reorder(Arel.sql(featured), *columns)
    else
      scope.reorder(*columns)
    end
  end

  def sort_columns
    case sort
    when "newest"          then [ { published_at: :desc }, { id: :desc } ]
    when "price_asc"       then [ { price_cents: :asc }, { id: :desc } ]
    when "price_desc"      then [ { price_cents: :desc }, { id: :desc } ]
    when "most_favorited"  then [ { favorites_count: :desc }, { published_at: :desc }, { id: :desc } ]
    else                                                     # best_match
      if @params[:q].present?
        rank = Listing.sanitize_sql_array(
          [ "ts_rank(listings.tsv, websearch_to_tsquery('simple', ?)) DESC", @params[:q] ]
        )
        [ Arel.sql(rank), { id: :desc } ]
      else
        [ { published_at: :desc }, { id: :desc } ]
      end
    end
  end

  # --- pagination ------------------------------------------------------------

  def build_pagy(total)
    options = { limit: @limit, page: @params[:page], count: total }
    options[:request] = Pagy::Request.new(request: @request) if @request
    Pagy::Offset.new(**options)
  end

  # Eager loading for the listing cards (kills the N+1 on store/user/photos).
  def with_card_includes(scope)
    scope.with_attached_photos
         .includes(:store, :user, :category, :labels, photos_attachments: :blob)
  end

  # --- facets ----------------------------------------------------------------

  # ONE grouped query, run over the filtered scope (before pagination and
  # before the card eager-loads). It counts the jsonb spec values plus the
  # condition enum and the labels / seller_tags join tables in the same pass,
  # so the sidebar can show counts and hide empty options without further
  # queries.
  #
  # Note: counts are for the current result set, i.e. they reflect filters
  # already applied (including the same facet's own selection).
  def facet_counts(scope)
    base = scope.select(:id, :specs, :condition).to_sql

    rows = Listing.connection.select_all(<<~SQL)
      WITH scoped AS (#{base})
      SELECT counts.key, counts.value, COUNT(*)::int AS count
      FROM (
        SELECT 'condition' AS key, scoped.condition::text AS value FROM scoped
        UNION ALL
        SELECT 'label', l.slug
        FROM scoped AS s
        JOIN listing_labels AS ll ON ll.listing_id = s.id
        JOIN labels AS l ON l.id = ll.label_id
        UNION ALL
        SELECT 'seller_tag', t.slug
        FROM scoped AS s
        JOIN listing_tags AS lt ON lt.listing_id = s.id
        JOIN seller_tags AS t ON t.id = lt.seller_tag_id
        UNION ALL
        SELECT e.key, expanded.value
        FROM scoped AS s
        CROSS JOIN LATERAL jsonb_each(s.specs) AS e(key, value)
        CROSS JOIN LATERAL (
          SELECT jsonb_array_elements_text(
            CASE WHEN jsonb_typeof(e.value) = 'array' THEN e.value ELSE jsonb_build_array(e.value) END
          ) AS value
        ) AS expanded
      ) AS counts
      GROUP BY 1, 2
    SQL

    rows.each_with_object({}) do |row, facets|
      (facets[row["key"]] ||= {})[row["value"]] = row["count"]
    end
  end

  # Spec attributes to render as facet groups: the category's own (ancestors
  # included) when a category is selected, otherwise whichever facet attributes
  # actually appear in the results.
  def facet_attributes_for(facets)
    keys = facets.keys - COLUMN_FACETS
    return [] if keys.empty?

    if category
      category.all_spec_attributes.select(&:facet?)
    else
      SpecAttribute.filterable.where(key: keys).includes(:spec_options).order(:position).select(&:facet?)
    end
  end

  # --- normalised inputs (for chips / form re-render) -------------------------

  def normalized_filters
    {
      q: @params[:q].presence,
      category: category,
      min_cents: euros_to_cents(@params[:min_price]),
      max_cents: euros_to_cents(@params[:max_price]),
      conditions: Array(@params[:condition]).map(&:to_s) & Listing.conditions.keys,
      specs: specs,
      labels: labels,
      tags: tags,
      seller: seller,
      sort: sort,
      page: @params[:page].to_s.presence
    }
  end

  def specs
    raw = @params[:f]
    return {} if raw.blank?

    raw.each_with_object({}) do |(key, values), out|
      list = Array(values).map(&:to_s).reject(&:blank?)
      out[key.to_s] = list if list.any?
    end
  end

  # Selected labels / seller tags, validated against their tables. One query
  # each, reused both for the scope filter and for the applied-filter chips.
  def label_rows
    @label_rows ||= Label.where(slug: Array(@params[:labels])).pluck(:id, :slug)
  end

  def tag_rows
    @tag_rows ||= SellerTag.where(slug: Array(@params[:tags])).pluck(:id, :slug)
  end

  def labels
    label_rows.map(&:last)
  end

  def tags
    tag_rows.map(&:last)
  end

  def filterable_attributes_by_key
    @filterable_attributes_by_key ||=
      SpecAttribute.filterable.where(key: specs.keys).select(&:facet?).index_by(&:key)
  end

  def euros_to_cents(value)
    return nil if value.blank?

    amount = BigDecimal(value.to_s)
    (amount * 100).round
  rescue ArgumentError
    nil
  end
end
