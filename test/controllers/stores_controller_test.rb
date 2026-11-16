require "test_helper"

class StoresControllerTest < ActionDispatch::IntegrationTest
  test "store page is public and shows the seller's listings" do
    get "/en/stores/one-store"
    assert_response :success
    assert_match(/One Store/, response.body)
    assert_match(/Gigabyte RTX 4070 Gaming OC/, response.body)
    assert_no_match(/Barely used RTX 4060/, response.body)
  end

  test "unknown store is 404" do
    get "/en/stores/not-a-store"
    assert_response :not_found
  end

  test "tab param selects about and reviews tabs" do
    get "/en/stores/one-store", params: { tab: "about" }
    assert_response :success

    get "/en/stores/one-store", params: { tab: "reviews" }
    assert_response :success

    get "/en/stores/one-store", params: { tab: "nonsense" }
    assert_response :success
  end

  test "anonymous store page is cacheable by shared caches" do
    get "/en/stores/one-store"
    assert_response :success
    assert_match(/\bpublic\b/, response.headers["Cache-Control"])
    assert_no_match(/\bprivate\b/, response.headers["Cache-Control"])
  end

  test "store page for a signed-in owner stays private" do
    sign_in_as(users(:one))
    get "/en/stores/one-store"
    assert_response :success
    assert_match(/\bprivate\b/, response.headers["Cache-Control"])
    assert_no_match(/\bpublic\b/, response.headers["Cache-Control"])
  end

  test "store page supports conditional GET" do
    get "/en/stores/one-store"
    etag = response.headers["ETag"]
    assert etag.present?

    get "/en/stores/one-store", headers: { "If-None-Match" => etag }
    assert_response :not_modified
  end
end
