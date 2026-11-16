require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "home responds to /es" do
    get "/es"
    assert_response :success
  end

  test "home responds to /en" do
    get "/en"
    assert_response :success
  end

  test "home responds without a locale and falls back to the default" do
    get "/"
    assert_response :success
  end
end
