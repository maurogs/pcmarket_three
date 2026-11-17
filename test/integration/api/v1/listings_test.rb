require "test_helper"

# Catalogue reads: ListingSearch owns filters, facets, sort and pagination; the
# controller only adds the Link header and the conditional-GET ETag.
class Api::V1::ListingsTest < ActionDispatch::IntegrationTest
  # Approved fixtures, newest first (browse shows approved listings in the
  # caller's country only; draft/pending/rejected stay invisible).
  NEWEST_FIRST = %w[
    ryzen-7-5800x3d-value-build
    budget-rtx-3060-starter-pc
    mid-range-ryzen-5-gaming-desktop
    custom-rtx-4080-super-gaming-pc
    barely-used-rtx-4060
    gigabyte-rtx-4070-gaming-oc
    featured-zotac-rtx-4070-super
  ].freeze

  test "index returns cards with pagination meta and the Link header" do
    get "/api/v1/listings", params: { sort: "newest", page: 1, limit: 2 }, headers: json_api_headers
    assert_response :success
    body = json_body
    assert_equal NEWEST_FIRST.first(2), body[:listings].map { |l| l[:slug] }

    card = body[:listings].first
    %w[slug title status condition condition_label price_money city store web_url].each do |key|
      assert card.key?(key.to_sym), "expected the card to carry #{key}"
    end
    assert_equal %i[cents currency formatted], card[:price_money].keys.sort

    assert_equal({ page: 1, per_page: 2, total: 7, total_pages: 4 }, body[:meta][:pagination])

    link = response.headers["Link"]
    assert_includes link, "rel=\"first\""
    assert_includes link, "rel=\"next\""
    assert_includes link, "page=4"
    assert_not_includes link, "rel=\"prev\""
  end

  test "the last page carries a prev link instead of a next one" do
    get "/api/v1/listings", params: { sort: "newest", page: 4, limit: 2 }, headers: json_api_headers
    assert_response :success

    assert_equal [ NEWEST_FIRST.last ], json_body[:listings].map { |l| l[:slug] }
    link = response.headers["Link"]
    assert_includes link, "rel=\"prev\""
    assert_not_includes link, "rel=\"next\""
  end

  test "conditions narrow the set and echo back in meta.filters" do
    get "/api/v1/listings", params: { condition: %w[brand_new used_good] }, headers: json_api_headers
    assert_response :success

    assert_equal %w[budget-rtx-3060-starter-pc gigabyte-rtx-4070-gaming-oc
                    mid-range-ryzen-5-gaming-desktop],
                 json_body[:listings].map { |l| l[:slug] }.sort
    assert_equal %w[brand_new used_good], json_body[:meta][:filters][:conditions]
  end

  test "price bounds and sort are applied" do
    get "/api/v1/listings", params: { min_price: "900", sort: "price_asc" }, headers: json_api_headers
    assert_equal %w[mid-range-ryzen-5-gaming-desktop custom-rtx-4080-super-gaming-pc],
                 json_body[:listings].map { |l| l[:slug] }

    get "/api/v1/listings", params: { max_price: "340" }, headers: json_api_headers
    assert_equal %w[barely-used-rtx-4060], json_body[:listings].map { |l| l[:slug] }
  end

  test "labels, seller tags, store and category filters are applied" do
    get "/api/v1/listings", params: { labels: %w[open-box] }, headers: json_api_headers
    assert_equal %w[featured-zotac-rtx-4070-super gigabyte-rtx-4070-gaming-oc],
                 json_body[:listings].map { |l| l[:slug] }.sort

    get "/api/v1/listings", params: { tags: %w[watercooled] }, headers: json_api_headers
    assert_equal %w[barely-used-rtx-4060 gigabyte-rtx-4070-gaming-oc],
                 json_body[:listings].map { |l| l[:slug] }.sort

    get "/api/v1/listings", params: { seller: "two-store" }, headers: json_api_headers
    assert_equal %w[barely-used-rtx-4060 mid-range-ryzen-5-gaming-desktop
                    ryzen-7-5800x3d-value-build],
                 json_body[:listings].map { |l| l[:slug] }.sort

    get "/api/v1/listings", params: { category: "rtx-series" }, headers: json_api_headers
    assert_equal %w[barely-used-rtx-4060 featured-zotac-rtx-4070-super],
                 json_body[:listings].map { |l| l[:slug] }.sort
    assert_equal "rtx-series", json_body[:meta][:filters][:category]
  end

  test "facets are value/count buckets keyed by attribute" do
    get "/api/v1/listings", headers: json_api_headers
    facets = body_facets

    conditions = facets[:condition].index_by { |b| b[:value] }
    assert_equal 1, conditions.fetch("brand_new")[:count]
    assert_equal 4, conditions.fetch("used_like_new")[:count]
    assert_equal 2, conditions.fetch("used_good")[:count]

    labels = facets[:label].index_by { |b| b[:value] }
    assert_equal 2, labels.fetch("open-box")[:count]
  end

  test "f[attribute] spec filters narrow the set and are echoed in meta" do
    get "/api/v1/listings", params: { f: { vram: %w[12GB] } }, headers: json_api_headers
    assert_response :success

    assert_equal %w[featured-zotac-rtx-4070-super gigabyte-rtx-4070-gaming-oc],
                 json_body[:listings].map { |l| l[:slug] }.sort
    assert_equal({ vram: %w[12GB] }, json_body[:meta][:filters][:specs])

    # The spec attribute rides along in the facet buckets of an unfiltered
    # query, so a client can build its filter sheet from the same response
    # (a filtered query re-counts facets over the narrowed scope).
    get "/api/v1/listings", headers: json_api_headers
    vram = body_facets[:vram].index_by { |b| b[:value] }
    assert_equal({ "12GB" => 2, "8GB" => 1 }, vram.transform_values { |b| b[:count] })

    # OR inside one attribute, AND across attributes.
    get "/api/v1/listings", params: { f: { vram: %w[12GB 8GB], negotiable: %w[true] } },
                            headers: json_api_headers
    assert_equal %w[barely-used-rtx-4060], json_body[:listings].map { |l| l[:slug] }
  end

  test "the full-text query is searchable" do
    get "/api/v1/listings", params: { q: "Zotac" }, headers: json_api_headers
    assert_response :success
    assert_equal %w[featured-zotac-rtx-4070-super], json_body[:listings].map { |l| l[:slug] }
  end

  test "the index answers If-None-Match with 304 and no body" do
    get "/api/v1/listings", params: { page: 1, limit: 2 }, headers: json_api_headers
    etag = response.headers["ETag"]
    assert etag.present?

    get "/api/v1/listings", params: { page: 1, limit: 2 },
        headers: json_api_headers.merge("If-None-Match" => etag)
    assert_response :not_modified
    assert response.body.blank?
  end

  test "show returns the full listing with description, specs and tags" do
    get "/api/v1/listings/#{listings(:gigabyte).slug}", headers: json_api_headers
    assert_response :success

    listing = json_body[:listing]
    assert_equal listings(:gigabyte).id, listing[:id]
    assert listing[:description].present?
    assert_equal({ vram: "12GB", negotiable: false }, listing[:specs])
    assert_equal %w[watercooled], listing[:seller_tags]
    assert listing.key?(:photos)
    assert_equal "graphics-cards", listing[:category][:slug]
  end

  test "a draft listing 404s for strangers but not for its owner" do
    draft = listings(:draft)

    get "/api/v1/listings/#{draft.slug}", headers: json_api_headers
    assert_response :not_found
    assert_equal "not_found", json_body[:error][:code]

    auth_as users(:two)
    get "/api/v1/listings/#{draft.slug}", headers: json_api_headers
    assert_response :success
    assert_equal draft.slug, json_body[:listing][:slug]
  end

  test "show answers If-None-Match with 304" do
    get "/api/v1/listings/#{listings(:gigabyte).id}", headers: json_api_headers
    etag = response.headers["ETag"]
    assert etag.present?

    get "/api/v1/listings/#{listings(:gigabyte).id}",
        headers: json_api_headers.merge("If-None-Match" => etag)
    assert_response :not_modified
  end

  test "the index stays free of per-row queries" do
    # Warm the process first (first request pays for Setting/Country lookups).
    get "/api/v1/listings", params: { limit: 5 }, headers: json_api_headers
    assert_response :success

    small = api_query_count { get "/api/v1/listings", params: { limit: 5 }, headers: json_api_headers }
    assert_equal 5, json_body[:listings].size

    large = api_query_count { get "/api/v1/listings", params: { limit: 100 }, headers: json_api_headers }
    assert_equal 7, json_body[:listings].size

    # The invariant is flat fan-out, not byte-identical counts: the limit-100
    # page happens to include the two labelled listings that the limit-5 page
    # misses, and Active Record then runs one genuinely extra eager load
    # (`Label Load`) it skipped entirely when no join rows came back. A per-row
    # loop over 100 rows would blow far past both bounds.
    assert_operator large, :<=, small + 1, "a bigger page must not add queries (N+1 guard)"
    assert_operator large, :<=, 16, "expected a bounded query count, got #{large}"
  end

  private

  def body_facets
    json_body[:meta][:facets]
  end
end
