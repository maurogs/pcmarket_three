require "test_helper"

class ListingSearchTest < ActiveSupport::TestCase
  def search(params = {})
    ListingSearch.new(params).call
  end

  def slugs(result)
    result.records.map(&:slug)
  end

  # Fixture set of approved ES listings: gigabyte (599.99, brand_new, rtx 4070),
  # as_new (330.00, used_like_new, rtx 4060), featured (650.00, used_like_new),
  # plus the gaming PCs beast (1899.00, like new), mid (1099.00, good),
  # budget (649.00, good) and value (599.00, like new).

  test "returns only approved listings" do
    assert_equal %w[barely-used-rtx-4060 budget-rtx-3060-starter-pc
                    custom-rtx-4080-super-gaming-pc featured-zotac-rtx-4070-super
                    gigabyte-rtx-4070-gaming-oc mid-range-ryzen-5-gaming-desktop
                    ryzen-7-5800x3d-value-build],
                 slugs(search).sort
    assert_equal 7, search.total_count
  end

  # --- q ---------------------------------------------------------------------

  test "q matches title and description via the simple-dictionary tsvector" do
    assert_equal 5, search(q: "rtx").total_count
    assert_equal %w[featured-zotac-rtx-4070-super gigabyte-rtx-4070-gaming-oc], slugs(search(q: "4070"))
    assert_equal %w[gigabyte-rtx-4070-gaming-oc], slugs(search(q: "sealed"))
    assert_equal 0, search(q: "nonexistent-gadget").total_count
  end

  # --- category + descendants --------------------------------------------------

  test "category matches the category itself and all of its descendants" do
    assert_equal 3, search(category: "graphics-cards").total_count
    assert_equal %w[barely-used-rtx-4060 featured-zotac-rtx-4070-super],
                 slugs(search(category: "rtx-series")).sort
  end

  test "unknown category slug matches nothing" do
    assert_equal 0, search(category: "not-a-category").total_count
  end

  # --- price -------------------------------------------------------------------

  test "min_price and max_price are euros compared against cents" do
    assert_equal %w[budget-rtx-3060-starter-pc custom-rtx-4080-super-gaming-pc
                    featured-zotac-rtx-4070-super gigabyte-rtx-4070-gaming-oc
                    mid-range-ryzen-5-gaming-desktop ryzen-7-5800x3d-value-build],
                 slugs(search(min_price: "400")).sort
    assert_equal %w[barely-used-rtx-4060], slugs(search(max_price: "400"))
    assert_equal 2, search(min_price: "500", max_price: "601").total_count
  end

  # --- condition ----------------------------------------------------------------

  test "condition filters by enum keys" do
    assert_equal %w[gigabyte-rtx-4070-gaming-oc], slugs(search(condition: [ "brand_new" ]))
    assert_equal %w[barely-used-rtx-4060 custom-rtx-4080-super-gaming-pc
                    featured-zotac-rtx-4070-super ryzen-7-5800x3d-value-build],
                 slugs(search(condition: %w[used_like_new])).sort
    assert_equal 0, search(condition: [ "for_parts" ]).total_count
    # unknown enum keys are ignored rather than raising
    assert_equal 7, search(condition: [ "bogus" ]).total_count
  end

  # --- specs jsonb containment ---------------------------------------------------

  test "options inside one attribute are OR-ed" do
    assert_equal 3, search(f: { vram: %w[8GB 12GB] }).total_count
    assert_equal %w[barely-used-rtx-4060], slugs(search(f: { vram: [ "8GB" ] }))
  end

  test "across attributes the groups are AND-ed" do
    assert_equal %w[barely-used-rtx-4060],
                 slugs(search(f: { vram: [ "8GB" ], negotiable: [ "true" ] }))
    assert_equal 0, search(f: { vram: [ "12GB" ], negotiable: [ "true" ] }).total_count
  end

  test "boolean spec values match true and false" do
    assert_equal %w[barely-used-rtx-4060], slugs(search(f: { negotiable: [ "true" ] }))
    assert_equal %w[featured-zotac-rtx-4070-super gigabyte-rtx-4070-gaming-oc],
                 slugs(search(f: { negotiable: [ "false" ] })).sort
  end

  test "array-valued specs match with containment on either form" do
    assert_equal %w[barely-used-rtx-4060], slugs(search(f: { ports: [ "hdmi" ] }))
    assert_equal %w[barely-used-rtx-4060], slugs(search(f: { ports: %w[hdmi displayport] }))
    assert_equal 0, search(f: { ports: [ "usb-c" ] }).total_count
  end

  test "non-filterable spec keys are ignored" do
    assert_equal 7, search(f: { not_a_real_key: [ "x" ] }).total_count
  end

  # --- labels / seller tags / seller ----------------------------------------------

  test "labels[] filters by label slug" do
    assert_equal %w[featured-zotac-rtx-4070-super gigabyte-rtx-4070-gaming-oc],
                 slugs(search(labels: [ "open-box" ])).sort
  end

  test "tags[] filters by seller tag slug" do
    assert_equal %w[barely-used-rtx-4060 gigabyte-rtx-4070-gaming-oc],
                 slugs(search(tags: [ "watercooled" ])).sort
  end

  test "seller filters by store slug" do
    assert_equal %w[ryzen-7-5800x3d-value-build mid-range-ryzen-5-gaming-desktop barely-used-rtx-4060],
                 slugs(search(seller: "two-store"))
    assert_equal 4, search(seller: "one-store").total_count
  end

  # --- sorting ---------------------------------------------------------------------

  test "newest sorts by published_at desc" do
    assert_equal %w[ryzen-7-5800x3d-value-build budget-rtx-3060-starter-pc
                    mid-range-ryzen-5-gaming-desktop custom-rtx-4080-super-gaming-pc
                    barely-used-rtx-4060 gigabyte-rtx-4070-gaming-oc featured-zotac-rtx-4070-super],
                 slugs(search(sort: "newest"))
  end

  test "price sorts" do
    assert_equal %w[barely-used-rtx-4060 ryzen-7-5800x3d-value-build gigabyte-rtx-4070-gaming-oc
                    budget-rtx-3060-starter-pc featured-zotac-rtx-4070-super
                    mid-range-ryzen-5-gaming-desktop custom-rtx-4080-super-gaming-pc],
                 slugs(search(sort: "price_asc"))
    assert_equal %w[custom-rtx-4080-super-gaming-pc mid-range-ryzen-5-gaming-desktop
                    featured-zotac-rtx-4070-super budget-rtx-3060-starter-pc
                    gigabyte-rtx-4070-gaming-oc ryzen-7-5800x3d-value-build barely-used-rtx-4060],
                 slugs(search(sort: "price_desc"))
  end

  test "most_favorited sorts by favorites_count desc" do
    assert_equal "barely-used-rtx-4060", slugs(search(sort: "most_favorited")).first
  end

  test "unknown sort falls back to best_match (published_at desc without q)" do
    assert_equal slugs(search(sort: "newest")), slugs(search(sort: "nonsense"))
  end

  test "featured listings come first only when the flipper flag is on" do
    assert_equal "ryzen-7-5800x3d-value-build", slugs(search).first

    Flipper.enable(:featured_listings)
    assert_equal "featured-zotac-rtx-4070-super", slugs(search).first
  ensure
    Flipper.disable(:featured_listings)
  end

  # --- pagination ---------------------------------------------------------------------

  test "limit and page window the result set" do
    result = ListingSearch.new({}, limit: 2).call
    assert_equal 2, result.records.size
    assert_equal 7, result.pagy.count
    assert_equal 4, result.pagy.pages

    page2 = ListingSearch.new({ page: "2" }, limit: 2).call
    assert_equal 2, page2.records.size
    assert_not_equal slugs(result), slugs(page2)
  end

  # --- facets ---------------------------------------------------------------------------

  test "facet counts come from a single grouped query" do
    queries = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      queries += 1 unless payload[:name] == "SCHEMA"
    end

    ListingSearch.new({}).call
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
    # scope count + page of records + ONE facet query + eager loads for the page.
    assert_operator queries, :<=, 12, "expected bounded queries, got #{queries}"
  end

  test "facets cover condition, spec values, labels and seller tags" do
    facets = search.facets
    assert_equal({ "0" => 1, "2" => 4, "3" => 2 }, facets["condition"])
    assert_equal({ "12GB" => 2, "8GB" => 1 }, facets["vram"])
    assert_equal({ "true" => 1, "false" => 2 }, facets["negotiable"])
    assert_equal({ "hdmi" => 1, "displayport" => 1 }, facets["ports"])
    assert_equal({ "open-box" => 2, "local-pickup-only" => 1 }, facets["label"])
    assert_equal({ "watercooled" => 2, "aio-cooling" => 1, "air-cooling" => 1,
                   "competitive" => 1, "silent-build" => 1 }, facets["seller_tag"])
  end

  test "facet_count translates condition enum keys" do
    result = search
    assert_equal 4, result.facet_count("condition", "used_like_new")
    assert_equal 1, result.facet_count("condition", "brand_new")
    assert_equal 0, result.facet_count("condition", "for_parts")
    assert_equal 1, result.facet_count("vram", "8GB")
    assert_equal 2, result.facet_count("label", "open-box")
    assert_equal 2, result.facet_count("seller_tag", "watercooled")
  end

  test "facet counts reflect the applied filters" do
    assert_equal 1, search(f: { vram: [ "8GB" ] }).facet_count("negotiable", "true")
    assert_equal 0, search(f: { vram: [ "8GB" ] }).facet_count("negotiable", "false")
  end

  test "facet_attributes lists the category's facet attributes when a category is set" do
    attrs = search(category: "graphics-cards").facet_attributes.map(&:key)
    assert_equal %w[negotiable ports vram], attrs.sort
  end

  test "facet_attributes falls back to attributes present in results without a category" do
    attrs = search.facet_attributes.map(&:key)
    assert_equal %w[negotiable ports vram], attrs.sort
    assert_equal %w[cpu_model gpu_model negotiable ports vram], search.spec_facets.keys.sort
  end

  # --- filters echo ----------------------------------------------------------------------

  test "applied_filters? is false for the bare search" do
    assert_not search.applied_filters?
    assert search(q: "rtx").applied_filters?
    assert search(category: "graphics-cards").applied_filters?
  end

  test "filters hash echoes normalised inputs" do
    result = search(q: "rtx", min_price: "10.50", condition: [ "brand_new" ], labels: [ "open-box" ])
    assert_equal "rtx", result.filters[:q]
    assert_equal 1050, result.filters[:min_cents]
    assert_equal %w[brand_new], result.filters[:conditions]
    assert_equal %w[open-box], result.filters[:labels]
    assert_equal "best_match", result.filters[:sort]
  end
end
