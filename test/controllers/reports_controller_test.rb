require "test_helper"

# "Report this listing" flow (Phase 7b). Signed-in only, public listings
# only, and the model's uniqueness rule surfaces as an unprocessable form.
class ReportsControllerTest < ActionDispatch::IntegrationTest
  test "anonymous visitors are sent to sign in" do
    get new_listing_report_path(listings(:gigabyte))
    assert_response :redirect
    assert_redirected_to new_session_path
  end

  test "non-public listings cannot be reported from the public side" do
    sign_in_as users(:two)

    get new_listing_report_path(listings(:pending))
    assert_response :not_found
  end

  test "the report form renders for a signed-in visitor" do
    sign_in_as users(:two)

    get new_listing_report_path(listings(:gigabyte))
    assert_response :success
    assert_select "h1", I18n.t("reports.new.title")
    assert_select "select[name='report[reason]']"
    assert_select "textarea[name='report[details]']"
  end

  test "a valid report is stored and redirects back to the listing" do
    sign_in_as users(:two)

    assert_difference "Report.count" do
      post listing_reports_path(listings(:gigabyte)),
           params: { report: { reason: "wrong_info", details: "The listing says 12GB, photos show 8GB." } }
    end

    assert_redirected_to listing_path(listings(:gigabyte))
    assert_equal I18n.t("reports.create.created"), flash[:notice]
    report = Report.last
    assert_equal users(:two), report.user
    assert_predicate report, :open?
  end

  test "reporting twice gets the unprocessable form" do
    sign_in_as users(:two)
    params = { report: { reason: "scam" } }

    post listing_reports_path(listings(:gigabyte)), params: params
    assert_response :redirect

    post listing_reports_path(listings(:gigabyte)), params: params
    assert_response :unprocessable_entity
    assert_equal Report.count, Report.count
  end

  test "a junk reason value never reaches enum assignment — 422 instead" do
    sign_in_as users(:two)

    assert_no_difference "Report.count" do
      post listing_reports_path(listings(:gigabyte)), params: { report: { reason: "nonsense" } }
    end
    assert_response :unprocessable_entity
  end

  test "the seller cannot report their own listing" do
    sign_in_as users(:one)

    post listing_reports_path(listings(:gigabyte)), params: { report: { reason: "other" } }

    assert_response :unprocessable_entity
    assert_equal 0, Report.count
  end
end
