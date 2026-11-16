require "test_helper"

class Sell::VacationModeTest < ActionDispatch::IntegrationTest
  setup do
    @store = stores(:two) # user two's store; as_new is user two's listing
  end

  test "toggle on and off from the dashboard" do
    sign_in_as users(:two)

    post sell_vacation_path
    assert_redirected_to sell_dashboard_path
    assert_equal I18n.t("sell.vacations.create.enabled"), flash[:notice]
    assert @store.reload.vacation_mode?

    delete sell_vacation_path
    assert_redirected_to sell_dashboard_path
    assert_equal I18n.t("sell.vacations.destroy.disabled"), flash[:notice]
    assert_not @store.reload.vacation_mode?
  end

  test "vacation listing keeps a public page but disables buying" do
    @store.enable_vacation!

    get listing_path(listings(:as_new))
    assert_response :success
    assert_match I18n.t("listings.show.vacation_banner", store: @store.name), response.body

    doc = Nokogiri::HTML(response.body)
    disabled = doc.css("button[disabled]").map(&:text)
    assert_includes disabled.map(&:strip), I18n.t("listings.show.buy_now")
    assert_includes disabled.map(&:strip), I18n.t("listings.show.make_offer")
  end

  test "listing pages are unaffected when the seller is active" do
    get listing_path(listings(:as_new))
    assert_response :success
    assert_no_match I18n.t("listings.show.vacation_banner", store: @store.name).gsub("%{store}", "Two Store"), response.body
  end

  test "store page shows the vacation banner and stays browsable" do
    @store.enable_vacation!

    get store_path(@store)
    assert_response :success
    assert_match I18n.t("stores.show.vacation_notice"), response.body
    assert_match "Barely used RTX 4060", response.body # listings are not hidden
  end
end
