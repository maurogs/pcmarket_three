require "test_helper"

class ListingsControllerTest < ActionDispatch::IntegrationTest
  # --- index / search ---------------------------------------------------------

  test "index lists approved listings only" do
    get "/en/listings"
    assert_response :success
    assert_select "h3", count: 7
    assert_no_match(/Used RTX 3080/, response.body)
    assert_no_match(/Sold ASUS ROG Strix/, response.body)
  end

  test "GET /search renders results without redirecting" do
    get "/en/search", params: { q: "rtx" }
    assert_response :ok
    assert_select "h3", count: 5
  end

  test "index filters from the query string" do
    get "/en/listings", params: { category: "rtx-series" }
    assert_response :success
    assert_select "h3", count: 2
    assert_match(/Barely used RTX 4060/, response.body)
  end

  test "index combines category and condition filters" do
    get "/en/listings", params: { category: "graphics-cards", condition: [ "brand_new" ] }
    assert_response :success
    assert_select "h3", count: 1
  end

  test "index paginates with a page param" do
    get "/en/listings", params: { page: "2" }
    assert_response :success
  end

  test "index inside a turbo frame still renders the results frame" do
    get "/en/listings", params: { q: "4070" },
        headers: { "Turbo-Frame" => "results" }
    assert_response :success
    assert_select "turbo-frame#results"
  end

  test "index does not run one query per card" do
    three = count_queries do
      get "/en/listings"
      assert_response :success
    end
    one = count_queries do
      get "/en/listings", params: { q: "4060" }
      assert_response :success
    end
    # Overhead is fixed (count + one facet query + eager loads): three cards
    # must not cost meaningfully more queries than one.
    assert_operator three, :<=, 24, "expected bounded queries, got #{three}"
    assert_operator three - one, :<=, 4, "query count scales with cards (3 cards=#{three}, 1 card=#{one})"
  end

  # --- show --------------------------------------------------------------------

  test "approved listing show is public" do
    get "/en/listings/#{listings(:gigabyte).slug}"
    assert_response :success
    assert_select "h1", text: listings(:gigabyte).title
  end

  test "sold listing is visible with a sold banner and no buy CTAs" do
    get "/en/listings/#{listings(:sold).slug}"
    assert_response :success
    assert_match(/Sold/, response.body)
    assert_no_match(/Buy now/, response.body)
    assert_no_match(/Make an offer/, response.body)
  end

  test "draft, pending and rejected listings are 404 for strangers" do
    %w[used-rtx-3080 pending-gpu-listing rejected-gpu-listing].each do |slug|
      get "/en/listings/#{slug}"
      assert_response :not_found, "#{slug} should not be public"
    end
  end

  test "the owner can see their own draft" do
    sign_in_as(users(:two))
    get "/en/listings/#{listings(:draft).slug}"
    assert_response :success
  end

  test "an admin can see any draft" do
    sign_in_as(users(:admin))
    get "/en/listings/#{listings(:draft).slug}"
    assert_response :success
  end

  test "unknown slug is 404" do
    get "/en/listings/not-a-real-listing"
    assert_response :not_found
  end

  test "show supports conditional GET with the etag" do
    get "/en/listings/#{listings(:gigabyte).slug}"
    etag = response.headers["ETag"]
    assert etag.present?

    get "/en/listings/#{listings(:gigabyte).slug}", headers: { "If-None-Match" => etag }
    assert_response :not_modified
  end

  test "anonymous GET of an approved listing is cacheable by shared caches" do
    get "/en/listings/#{listings(:gigabyte).slug}"
    assert_response :success
    assert_match(/\bpublic\b/, response.headers["Cache-Control"])
    assert_no_match(/\bprivate\b/, response.headers["Cache-Control"])
  end

  test "signed-in owner GET of a draft listing stays private" do
    sign_in_as(users(:two))
    get "/en/listings/#{listings(:draft).slug}"
    assert_response :success
    assert_match(/\bprivate\b/, response.headers["Cache-Control"])
    assert_no_match(/\bpublic\b/, response.headers["Cache-Control"])
  end

  test "signed-in admin GET of a pending listing stays private" do
    sign_in_as(users(:admin))
    get "/en/listings/#{listings(:pending).slug}"
    assert_response :success
    assert_match(/\bprivate\b/, response.headers["Cache-Control"])
    assert_no_match(/\bpublic\b/, response.headers["Cache-Control"])
  end

  test "signed-in GET of an approved listing stays private" do
    sign_in_as(users(:one))
    get "/en/listings/#{listings(:sold).slug}"
    assert_response :success
    assert_match(/\bprivate\b/, response.headers["Cache-Control"])
    assert_no_match(/\bpublic\b/, response.headers["Cache-Control"])
  end

  private

  def count_queries
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      count += 1 unless payload[:name] == "SCHEMA"
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
