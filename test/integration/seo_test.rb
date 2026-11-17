require "test_helper"

# Phase 8a: per-page meta tags, canonicals, hreflang, OG/Twitter and
# JSON-LD structured data.
class SeoTest < ActionDispatch::IntegrationTest
  HOST = "http://www.example.com".freeze

  test "home page carries a localized title, description and canonical" do
    get "/"
    assert_response :success
    assert_select "title", /#{Regexp.escape(I18n.t("site.name"))}/
    assert_match(/name="description" content="\S/, response.body)
    assert_select "link[rel=canonical][href=?]", "#{HOST}/"
    assert_select 'meta[property="og:type"][content=website]'
    assert_select 'meta[property="og:locale"][content=en_GB]'
    assert_select 'meta[property="og:image"][content=?]', "#{HOST}/og-default.png"
    assert_nil response.headers["X-Robots-Tag"]
  end

  test "indexable pages link hreflang alternates for all six locales plus x-default" do
    get "/"
    assert_select "link[rel=alternate][hreflang]", 7
    assert_select "link[rel=alternate][hreflang=es][href=?]", "#{HOST}/es"
    assert_select "link[rel=alternate][hreflang=en][href=?]", "#{HOST}/"
    assert_select "link[rel=alternate][hreflang=x-default][href=?]", "#{HOST}/"
  end

  test "non-default locale pages canonicalize to their locale-prefixed url" do
    get "/fr"
    assert_select "link[rel=canonical][href=?]", "#{HOST}/fr"
    assert_select 'meta[property="og:locale"][content=fr_FR]'
  end

  test "listing show canonicalizes to the slug url and strips tracking params" do
    get "/listings/gigabyte-rtx-4070-gaming-oc?utm_source=ads&gclid=x"
    assert_select "link[rel=canonical][href=?]", "#{HOST}/listings/gigabyte-rtx-4070-gaming-oc"
  end

  test "listing show renders product open graph and twitter tags" do
    get "/listings/gigabyte-rtx-4070-gaming-oc"
    assert_select 'meta[property="og:type"][content=product]'
    assert_select 'meta[property="og:title"][content=?]', "Gigabyte RTX 4070 Gaming OC"
    assert_select 'meta[property="og:image"][content=?]', "#{HOST}/og-default.png"
    assert_select 'meta[property="product:price:amount"][content=?]', "599.99"
    assert_select 'meta[property="product:price:currency"][content=?]', "EUR"
    assert_select 'meta[name="twitter:card"][content=summary_large_image]'
  end

  test "listing show carries a listing-title page title and a meta description" do
    get "/listings/gigabyte-rtx-4070-gaming-oc"
    assert_select "title", /#{Regexp.escape("Gigabyte RTX 4070 Gaming OC")}/
    assert_match(/name="description" content="\S/, response.body)
  end

  test "category pages title with the category name and carry a meta description" do
    get "/c/graphics-cards"
    assert_select "title", /#{Regexp.escape("Graphics Cards")}/
    assert_match(/name="description" content="\S/, response.body)
  end

  test "listing show exposes Product + BreadcrumbList JSON-LD without a rating" do
    get "/listings/gigabyte-rtx-4070-gaming-oc"
    product = json_ld_document("Product")
    assert_equal "Gigabyte RTX 4070 Gaming OC", product["name"]
    assert_equal listings(:gigabyte).id.to_s, product["sku"]
    assert_equal "InStock", product["offers"]["availability"]
    assert_equal "https://schema.org/NewCondition", product["offers"]["itemCondition"]
    assert_nil product["aggregateRating"]
    breadcrumb = json_ld_document("BreadcrumbList")
    assert_equal 3, breadcrumb["itemListElement"].size
  end

  test "sold listings mark their offer SoldOut in structured data" do
    get "/listings/sold-asus-rog-strix-rtx-3070"
    assert_response :success
    product = json_ld_document("Product")
    assert_equal "SoldOut", product["offers"]["availability"]
    assert_equal "https://schema.org/UsedCondition", product["offers"]["itemCondition"]
  end

  test "home page exposes Organization and WebSite structured data" do
    get "/"
    assert_equal "Organization", json_ld_document("Organization")["@type"]
    assert_equal "WebSite", json_ld_document("WebSite")["@type"]
  end

  test "category canonical keeps content filters but drops sort and first page" do
    get "/c/graphics-cards?condition=brand_new&sort=price_asc&page=2&utm_source=x"
    assert_select "link[rel=canonical][href=?]",
                  "#{HOST}/c/graphics-cards?condition=brand_new&page=2"
  end

  test "category first page exposes an ItemList of its results" do
    get "/c/graphics-cards"
    item_list = json_ld_document("ItemList")
    assert_includes item_list["itemListElement"].map { |e| e["name"] },
                    "Gigabyte RTX 4070 Gaming OC"
  end

  test "help page exposes FAQPage structured data" do
    get "/pages/help"
    faq = json_ld_document("FAQPage")
    assert_equal "FAQPage", faq["@type"]
    assert_operator faq["mainEntity"].size, :>=, 15
    assert(faq["mainEntity"].all? { |q| q["@type"] == "Question" && q["acceptedAnswer"]["text"].present? })
  end

  # JSON-LD safety: ActiveSupport's to_json escapes "<" as \u003c, so a
  # hostile title cannot close the <script> element; the block must stay
  # valid JSON and must not execute anything.
  test "a listing title containing a script breakout yields JSON-LD that still parses" do
    hostile_title = %(Broken RTX Card </script><script>alert(1)</script>)
    listing = Listing.create!(
      user: users(:one), store: stores(:one), category: categories(:gpus),
      title: hostile_title, description: "JSON-LD escaping test",
      price_cents: 20_000, condition: "used_good"
    )
    listing.update!(status: :approved, published_at: Time.current)

    get "/listings/#{listing.slug}"
    assert_response :success

    scripts = css_select("script[type='application/ld+json']")
    assert_equal 1, scripts.size
    raw_json = scripts.first.inner_html

    assert_not_includes raw_json, "</script>"
    assert_not_includes response.body, "<script>alert(1)</script>"

    document = JSON.parse(raw_json)
    product = document.fetch("@graph", []).find { |node| node["@type"] == "Product" }
    assert_equal hostile_title, product["name"]
    assert_equal listing.id.to_s, product["sku"]
  end

  test "free-text search results are noindexed" do
    get "/listings?q=rtx"
    assert_select "meta[name=robots][content=?]", "noindex,follow"
    assert_select "link[rel=alternate]", 0
  end

  test "empty result pages are noindexed" do
    get "/listings?q=zzzz-nothing-matches"
    assert_select "meta[name=robots][content=?]", "noindex,follow"
  end

  test "browse pages with more than two filter groups are noindexed" do
    # condition + price band + labels = 3 groups; the query still has results,
    # so this isolates the >2-filters rule from the empty-results rule.
    get "/c/graphics-cards?condition[]=brand_new&min_price=1&max_price=1000&labels[]=open-box"
    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex,follow"
  end

  test "browse pages with two filter groups stay indexable" do
    get "/c/graphics-cards?condition[]=brand_new&min_price=1&max_price=1000"
    assert_response :success
    assert_select "meta[name=robots][content=?]", "index,follow"
  end

  test "finder results keep the finder params in the canonical" do
    get "/pc-finder/results?game=cyberpunk-2077&resolution=1080p&sort=price_asc"
    assert_select "link[rel=canonical][href=?]",
                  "#{HOST}/pc-finder/results?game=cyberpunk-2077&resolution=1080p"
  end

  test "private areas are noindexed, in the meta tag and the response header" do
    sign_in_as users(:one)
    [ "/account/profile", "/sell" ].each do |path|
      get path
      assert_response :success
      assert_select "meta[name=robots][content=?]", "noindex,follow"
      assert_equal "noindex, follow", response.headers["X-Robots-Tag"], path
    end

    sign_in_as users(:admin)
    get "/admin"
    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex,follow"
    assert_equal "noindex, follow", response.headers["X-Robots-Tag"]
  end

  test "cart and checkout pages are noindexed" do
    sign_in_as users(:one)
    CartItem.create!(cart: Cart.for_user(users(:one)), listing: listings(:gigabyte), quantity: 1)

    get "/cart"
    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex,follow"
    assert_equal "noindex, follow", response.headers["X-Robots-Tag"]

    get "/checkout"
    assert_response :success
    assert_select "meta[name=robots][content=?]", "noindex,follow"
    assert_equal "noindex, follow", response.headers["X-Robots-Tag"]
  end

  test "auth pages are noindexed" do
    [ "/session/new", "/registration/new", "/passwords/new" ].each do |path|
      get path
      assert_response :success
      assert_select "meta[name=robots][content=?]", "noindex,follow"
      assert_equal "noindex, follow", response.headers["X-Robots-Tag"], path
    end
  end

  private

  def json_ld_document(type)
    docs = css_select("script[type='application/ld+json']").filter_map do |script|
      JSON.parse(script.inner_html)
    end
    docs.filter_map { |doc|
      next doc if doc["@type"] == type

      doc.fetch("@graph", []).find { |node| node["@type"] == type }
    }.first
  end
end
