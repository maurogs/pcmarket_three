require "test_helper"

class CategoriesControllerTest < ActionDispatch::IntegrationTest
  test "category page renders the shared browse UI for that category" do
    get "/en/c/graphics-cards"
    assert_response :success
    assert_select "turbo-frame#results"
    assert_match(/Graphics Cards/, response.body)
  end

  test "category page includes listings from descendant categories" do
    get "/en/c/graphics-cards"
    assert_match(/Barely used RTX 4060/, response.body)

    get "/en/c/rtx-series"
    assert_no_match(/Gigabyte RTX 4070 Gaming OC/, response.body)
  end

  test "unknown category slug is 404" do
    get "/en/c/not-a-category"
    assert_response :not_found
  end

  test "category page is localised" do
    get "/es/c/graphics-cards"
    assert_response :success
    assert_match(/<html lang="es"/, response.body)
  end

  test "anonymous category page is browser-cached only, never shared" do
    get "/en/c/graphics-cards"
    assert_response :success
    cache_control = response.headers["Cache-Control"]
    assert_match(/\bprivate\b/, cache_control)
    assert_no_match(/\bpublic\b/, cache_control)
    assert_match(/max-age=0\b/, cache_control)
    assert_match(/must-revalidate\b/, cache_control)
  end

  test "signed-in category page stays private" do
    sign_in_as users(:one)
    get "/en/c/graphics-cards"
    assert_response :success
    cache_control = response.headers["Cache-Control"]
    assert_match(/\bprivate\b/, cache_control)
    assert_no_match(/\bpublic\b/, cache_control)
    assert_no_match(/max-age=60\b/, cache_control)
  end
end
