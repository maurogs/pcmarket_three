require "test_helper"

# Admin reports inbox (Phase 7b): read + two closing verbs, each audited.
# Closing an already-closed report must not overwrite the first closure.
class Admin::ReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:admin)
    @report = Report.create!(listing: listings(:gigabyte), user: users(:two),
                             reason: :wrong_info, details: "Wrong VRAM in the title.")
  end

  test "index lists the report with its state and filter counts" do
    get admin_reports_path

    assert_response :success
    assert_includes response.body, "Wrong VRAM in the title."
    assert_includes response.body, I18n.t("admin.reports.index.states.open")
  end

  test "index filters by state and reason" do
    closed = Report.create!(listing: listings(:as_new), user: users(:one), reason: :scam)
    closed.close!("dismissed", admin: users(:admin))

    get admin_reports_path(state: "open")
    assert_response :success
    assert_includes response.body, "Wrong VRAM"
    assert_not_includes response.body, "Barely used RTX 4060"

    get admin_reports_path(state: "closed")
    assert_response :success
    assert_includes response.body, "Barely used RTX 4060"
    assert_not_includes response.body, "Wrong VRAM"

    get admin_reports_path(reason: "offensive")
    assert_response :success
    assert_includes response.body, I18n.t("admin.reports.index.empty")
  end

  test "show displays the report, its listing link and siblings" do
    Report.create!(listing: listings(:gigabyte), user: users(:admin), reason: :offensive)

    get admin_report_path(@report)
    assert_response :success
    assert_includes response.body, "Wrong VRAM in the title."
    assert_includes response.body, I18n.t("admin.reports.show.sibling_section", count: 2)
  end

  test "resolving closes the report, stamps the admin and writes an audit" do
    assert_difference "AdminAuditLog.where(action: 'report_resolve').count" do
      post admin_report_resolution_path(@report)
    end

    assert_redirected_to admin_report_path(@report)
    assert_equal I18n.t("admin.report_resolutions.create.resolved"), flash[:notice]

    @report.reload
    assert_predicate @report, :resolved_action_resolved?
    assert_equal users(:admin), @report.resolved_by
  end

  test "dismissing closes without touching the listing" do
    assert_difference "AdminAuditLog.where(action: 'report_dismiss').count" do
      post admin_report_dismissal_path(@report)
    end

    assert_redirected_to admin_report_path(@report)
    assert_equal I18n.t("admin.report_dismissals.create.dismissed"), flash[:notice]
    assert_predicate @report.reload, :resolved_action_dismissed?
    assert_predicate listings(:gigabyte).reload, :approved?
  end

  test "closing a second time bounces with a warning and keeps the first closure" do
    @report.close!("resolved", admin: users(:admin))
    first_closed_at = @report.resolved_at

    post admin_report_dismissal_path(@report)
    assert_redirected_to admin_report_path(@report)
    assert_equal I18n.t("admin.reports.show.already_closed"), flash[:alert]

    @report.reload
    assert_equal first_closed_at, @report.resolved_at
    assert_predicate @report, :resolved_action_resolved?
  end
end
