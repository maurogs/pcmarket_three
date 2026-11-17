require "test_helper"

# Phase 8a: localized error pages served through config.exceptions_app.
# In the test environment DebugExceptions renders its own page for
# unrouted urls, so content assertions go through the /404 and /500
# routes that exceptions_app itself re-dispatches to.
class ErrorPagesTest < ActionDispatch::IntegrationTest
  test "unknown urls return 404" do
    get "/fr/pagina-inexistente"
    assert_response :not_found
  end

  test "the localized not-found page renders in the language of the original path" do
    # In the test env unrouted urls render DebugExceptions, so the locale
    # recovery (from action_dispatch.original_path) is asserted directly
    # through the /404 route that exceptions_app dispatches to.
    get "/404", env: { "action_dispatch.original_path" => "/fr/pagina-inexistente" }
    assert_response :not_found
    assert_includes response.body, I18n.t("errors.not_found.title", locale: :fr)
    assert_select "html[lang=fr]"
  end

  test "the not-found page offers a search back to the listings" do
    get "/404"
    assert_response :not_found
    assert_select "h1", I18n.t("errors.not_found.title")
    assert_includes response.body, I18n.t("errors.not_found.lede")
    assert_select "form[action=?]", listings_path
    assert_select "input[name=q]"
    assert_match(/name="robots" content="[^"]*noindex/, response.body)
  end

  test "the server error page renders with status 500" do
    get "/500"
    assert_response :internal_server_error
    assert_select "h1", I18n.t("errors.internal_server_error.title")
    assert_select "title", /#{Regexp.escape(I18n.t("errors.internal_server_error.title"))}/
  end

  test "the unprocessable page renders with status 422" do
    get "/422"
    assert_response :unprocessable_entity
    assert_select "h1", I18n.t("errors.unprocessable.title")
  end
end
