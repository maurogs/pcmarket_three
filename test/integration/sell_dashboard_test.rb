require "test_helper"

class Sell::DashboardTest < ActionDispatch::IntegrationTest
  test "guests are sent to sign in from the dashboard" do
    get sell_dashboard_path
    assert_redirected_to new_session_path
  end

  test "dashboard renders KPIs and the sidebar for the signed-in seller" do
    sign_in_as users(:two)
    listings(:as_new).update_column(:views_count, 137)

    get sell_dashboard_path
    assert_response :success

    assert_select "h1", text: I18n.t("sell.dashboards.show.title")
    # sidebar store card
    assert_match "Two Store", response.body
    assert_match "@two", response.body
    # KPI tiles
    assert_match "137", response.body
    assert_match I18n.t("sell.dashboards.show.kpis.live_listings"), response.body
    # twelve bars in the weekly chart
    assert_select "div[role=img] > div > div", count: 12
    # needs attention: the rejected listing surfaces with its reason
    assert_match "Rejected GPU Listing", response.body
    assert_match "Photos unreadable", response.body
  end

  test "header account menu exposes the sell area links when signed in" do
    sign_in_as users(:two)
    get root_path
    assert_response :success
    assert_match I18n.t("nav.my_store"), response.body
    assert_select "a[href='#{sell_dashboard_path}']", minimum: 1
    assert_select "a[href='#{edit_sell_store_path}']", minimum: 1
  end

  test "sales index shows only the signed-in seller's orders" do
    sign_in_as users(:two)
    get sell_sales_path
    assert_response :success
    assert_match "PCM-2026-000001", response.body  # seller: two
    assert_no_match "PCM-2026-000002", response.body # seller: one
  end

  test "sale show is scoped to the seller and read-only" do
    sign_in_as users(:two)
    get sell_sale_path(orders(:one))
    assert_response :success
    assert_match "PCM-2026-000001", response.body
    assert_match I18n.t("sell.sales.show.net_revenue"), response.body

    get sell_sale_path(orders(:two))
    assert_response :not_found
  end
end
