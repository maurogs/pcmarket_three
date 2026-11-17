# frozen_string_literal: true

require "test_helper"

class Admin::TradeInsTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:admin) }

  def quoted_quote
    TradeIns::Quote.call(component_type: "gpu", model: "rtx4070",
                         condition: "good", has_box: true).record
  end

  test "non-admins get a 404" do
    sign_in_as users(:one)
    get admin_trade_ins_path
    assert_response :not_found
  end

  test "index lists quotes with amounts and sellers" do
    quote = quoted_quote
    get admin_trade_ins_path
    assert_response :success
    assert_select "h1", text: I18n.t("admin.trade_ins.index.title")
    assert_match "280.50", response.body
    assert_match I18n.t("admin.trade_ins.index.anonymous"), response.body
    assert_select "a[href=?]", admin_trade_in_path(quote)
  end

  test "show offers the allowed transitions only" do
    quote = quoted_quote
    get admin_trade_in_path(quote)
    assert_response :success
    assert_match TradeIn.human_attribute_name("status/quoted"), response.body
    assert_match I18n.t("admin.trade_ins.show.transitions.accepted"), response.body
    assert_no_match I18n.t("admin.trade_ins.show.transitions.paid"), response.body
  end

  test "transition updates status, flashes and audits" do
    quote = quoted_quote
    assert_difference -> { AdminAuditLog.count }, 1 do
      patch admin_trade_in_path(quote), params: { transition: "rejected" }
    end
    assert_redirected_to admin_trade_in_path(quote)
    assert_match I18n.t("admin.trade_ins.update.updated"), flash[:notice]
    assert_predicate quote.reload, :rejected?
    assert_equal "trade_in_rejected", AdminAuditLog.order(:id).last.action
  end

  test "invalid transitions are refused with an alert" do
    quote = quoted_quote
    assert_no_difference -> { AdminAuditLog.count } do
      patch admin_trade_in_path(quote), params: { transition: "paid" }
    end
    assert_redirected_to admin_trade_in_path(quote)
    assert_match I18n.t("admin.trade_ins.update.invalid_transition"), flash[:alert]
    assert_predicate quote.reload, :quoted?
  end

  test "opening a stale quote expires it automatically" do
    quote = quoted_quote
    quote.update_column(:expires_at, 2.days.ago)
    get admin_trade_in_path(quote)
    assert_response :success
    assert_predicate quote.reload, :expired?
    assert_match I18n.t("admin.trade_ins.show.terminal"), response.body
  end
end
