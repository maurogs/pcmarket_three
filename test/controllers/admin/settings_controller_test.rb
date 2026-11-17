require "test_helper"

# Site settings form (Phase 6b). Writes go through Admin::Settings::Update,
# which validates each field BEFORE touching any Setting row; maintenance
# mode, once on, 503s the public site while signed-in admins keep browsing.
class Admin::SettingsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:admin) }

  test "edit renders the grouped settings form" do
    get edit_admin_settings_path
    assert_response :ok
    assert_select "input[name='settings[site_name]']"
    assert_select "input[name='settings[commission_percent]']"
    assert_select "input[name='settings[maintenance_mode]']"
  end

  test "commission_percent of 25 is rejected and no setting is written" do
    patch admin_settings_path, params: form_params(commission_percent: "25")

    assert_response :unprocessable_entity
    assert_not flash.now[:alert].blank?
    assert_equal 0, Setting.get("commission_percent", 0)
    assert_includes response.body, I18n.t("admin.settings.edit.errors.out_of_range")
    assert_equal 0, AdminAuditLog.where(action: "settings_update").count
  end

  test "commission_percent of 5 is accepted, persisted and audited as one row" do
    assert_difference "AdminAuditLog.count" do
      patch admin_settings_path, params: form_params(commission_percent: "5")
    end
    assert_redirected_to edit_admin_settings_path
    assert_not flash[:notice].blank?
    assert_equal 5.0, Setting.get("commission_percent")

    audit = AdminAuditLog.last
    assert_equal "settings_update", audit.action
    assert_nil audit.subject
    assert_includes audit.details["keys"], "commission_percent"
  end

  test "an invalid e-mail re-renders the form without writing anything" do
    patch admin_settings_path, params: form_params(support_email: "not-an-email")

    assert_response :unprocessable_entity
    assert_includes response.body, I18n.t("admin.settings.edit.errors.invalid_email")
    assert_not Setting.where(key: "support_email").exists?
  end

  test "maintenance mode on: public pages answer 503 with the maintenance page, admins keep 200" do
    patch admin_settings_path, params: form_params(maintenance_mode: "1")
    assert_redirected_to edit_admin_settings_path
    assert_equal true, Setting.get("maintenance_mode")

    sign_out
    get root_path
    assert_response :service_unavailable
    # assert_select un-escapes entities (the body text contains an apostrophe).
    assert_select "h1", I18n.t("application.maintenance.title")
    assert_select "main p", text: I18n.t("application.maintenance.body")

    get listings_path
    assert_response :service_unavailable

    sign_in_as users(:admin)
    get root_path
    assert_response :ok
    get admin_dashboard_path
    assert_response :ok
  end

  test "maintenance mode off again restores the public site" do
    Setting.set("maintenance_mode", true)

    patch admin_settings_path, params: form_params(maintenance_mode: "0")
    assert_redirected_to edit_admin_settings_path
    assert_equal false, Setting.get("maintenance_mode")

    sign_out
    get root_path
    assert_response :ok
  end

  private

  # A complete, valid submission; tests override single fields.
  def form_params(overrides = {})
    {
      settings: {
        site_name: "PCMarket",
        support_email: "soporte@pcmarket.example",
        support_phone: "",
        commission_percent: "0",
        featured_price_cents: "0",
        featured_days: "7",
        min_offer_percent: "50",
        announcement_enabled: "0",
        announcement_text: {},
        maintenance_mode: "0",
        social_links: {},
        default_meta_description: {}
      }
    }.deep_merge(settings: overrides)
  end
end
