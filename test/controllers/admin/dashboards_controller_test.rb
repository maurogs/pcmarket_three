require "test_helper"

# Phase 7b: the dashboard flags an incomplete company legal identity (the
# footer/legal pages would render placeholder-free but thin), and the banner
# disappears once every LEGAL_IDENTITY_KEYS value is filled in.
class Admin::DashboardsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:admin) }

  test "incomplete legal identity shows the warning banner with a settings link" do
    Setting.set("legal_name", "PC Market Iberia S.L.") # one filled, the rest empty

    get admin_dashboard_path
    assert_response :ok
    assert_includes response.body, I18n.t("admin.dashboards.show.legal_identity_warning.title")
    assert_select "a[href='#{edit_admin_settings_path}']",
                  text: I18n.t("admin.dashboards.show.legal_identity_warning.cta")
  end

  test "complete legal identity hides the warning banner" do
    Setting::LEGAL_IDENTITY_KEYS.each { |key| Setting.set(key, "Value for #{key}") }
    assert_predicate Setting, :legal_identity_complete?

    get admin_dashboard_path
    assert_response :ok
    assert_not_includes response.body, I18n.t("admin.dashboards.show.legal_identity_warning.title")
  end
end
