require "test_helper"

# Feature flags console (Phase 6b): on/off + percentage rollouts drive the
# real Flipper gates, every write lands in AdminAuditLog, and enabling
# stripe_checkout without its env keys shows a warning (it never blocks).
class Admin::FeatureFlagsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:admin) }

  test "index lists the five registered flags with their states" do
    get admin_feature_flags_path
    assert_response :ok

    FeatureFlags::FEATURES.each_key do |key|
      assert_includes response.body, I18n.t(FeatureFlags::FEATURES.fetch(key).fetch(:description_key))
    end
  end

  test "switching a flag on changes Flipper state and writes an audit row" do
    assert_not Flipper.enabled?(:commissions)

    assert_difference "AdminAuditLog.count" do
      patch admin_feature_flag_path("commissions"), params: { switch: "on" }
    end
    assert_redirected_to admin_feature_flags_path
    assert Flipper.enabled?(:commissions)

    audit = AdminAuditLog.last
    assert_equal "feature_flag_update", audit.action
    assert_nil audit.subject
    assert_equal "commissions", audit.details["key"]
    assert_equal "on", audit.details["outcome"]
  end

  test "switching it back off disables the flag again (audited)" do
    Flipper.enable(:google_login)

    assert_difference "AdminAuditLog.count" do
      patch admin_feature_flag_path("google_login"), params: { switch: "off" }
    end
    assert_not Flipper.enabled?(:google_login)
    assert_equal "off", AdminAuditLog.last.details["outcome"]
  end

  test "percentage rollout sets the gate and clamps the value" do
    patch admin_feature_flag_path("sell_to_us"), params: { switch: "percentage", percentage: "30" }
    # Flipper models a percentage gate as a "conditional" state.
    assert_equal "conditional", Flipper["sell_to_us"].state.to_s
    assert_equal 30, Flipper["sell_to_us"].percentage_of_actors_value
    assert_equal "percentage:30", AdminAuditLog.last.details["outcome"]

    patch admin_feature_flag_path("sell_to_us"), params: { switch: "percentage", percentage: "500" }
    assert_equal 99, Flipper["sell_to_us"].percentage_of_actors_value
  end

  test "stripe_checkout without STRIPE env keys shows a warning when on" do
    with_env("STRIPE_SECRET_KEY" => nil, "STRIPE_WEBHOOK_SECRET" => nil) do
      Flipper.enable(:stripe_checkout)

      get admin_feature_flags_path
      assert_response :ok
      assert_includes response.body, I18n.t("admin.feature_flags.warnings.missing_stripe_env")
    end
  end

  test "no stripe warning once both env keys are present" do
    with_env("STRIPE_SECRET_KEY" => "sk_test_1", "STRIPE_WEBHOOK_SECRET" => "whsec_1") do
      Flipper.enable(:stripe_checkout)

      get admin_feature_flags_path
      assert_response :ok
      assert_not_includes response.body, I18n.t("admin.feature_flags.warnings.missing_stripe_env")
    end
  end

  test "commissions flag warns while commission_percent is 0 and stays silent above it" do
    assert_equal 0, Setting.get("commission_percent", 0).to_i
    Flipper.enable(:commissions)

    get admin_feature_flags_path
    assert_includes response.body, I18n.t("admin.feature_flags.warnings.commission_percent_zero")

    Setting.set("commission_percent", 5)
    get admin_feature_flags_path
    assert_not_includes response.body, I18n.t("admin.feature_flags.warnings.commission_percent_zero")
  end

  test "unknown flag ids 404 without touching Flipper or the audit log" do
    assert_no_difference "AdminAuditLog.count" do
      patch admin_feature_flag_path("not_a_flag"), params: { switch: "on" }
    end
    assert_response :not_found
    assert_not Flipper.enabled?("not_a_flag")
  end

  test "non-admin gets 404 on the flags console" do
    sign_in_as users(:two)

    get admin_feature_flags_path
    assert_response :not_found
    patch admin_feature_flag_path("commissions"), params: { switch: "on" }
    assert_response :not_found
    assert_not Flipper.enabled?(:commissions)
  end

  private

  def with_env(pairs)
    previous = pairs.keys.index_with { |key| ENV[key] }
    pairs.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
