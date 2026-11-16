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
end
