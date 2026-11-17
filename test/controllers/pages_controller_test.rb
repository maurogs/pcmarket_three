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

  PAGE_SLUGS = %w[about how-it-works selling help contact seller-guides].freeze

  PAGE_SLUGS.each do |slug|
    test "#{slug} page renders" do
      get "/es/pages/#{slug}"
      assert_response :success
      assert_no_match(/translation missing/, response.body)
    end
  end

  test "unknown page slug is a 404" do
    get "/es/pages/legal-notice"
    assert_response :not_found
  end
end
