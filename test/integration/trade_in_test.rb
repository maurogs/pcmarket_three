# frozen_string_literal: true

require "test_helper"

class TradeInTest < ActionDispatch::IntegrationTest
  setup { Flipper.enable(:sell_to_us) }
  teardown { Flipper.disable(:sell_to_us) }

  def create_quote(model: "gpu:rtx4070", condition: "good", has_box: "1")
    post trade_in_quotes_path, params: { model: model, condition: condition, has_box: has_box }
    assert_response :redirect
    TradeIn.order(:id).last
  end

  test "the whole flow 404s while the flag is off" do
    Flipper.disable(:sell_to_us)
    get new_trade_in_quote_path
    assert_response :not_found
    post trade_in_quotes_path, params: { model: "gpu:rtx4070", condition: "good" }
    assert_response :not_found

    quote = TradeIn.create!(component_type: :gpu, model: "rtx4070", condition: :good,
                            offered_cents: 28_050, expires_at: 7.days.from_now)
    sign_in_as users(:one)
    get trade_in_quote_path(quote)
    assert_response :not_found
    post trade_in_quote_acceptance_path(quote)
    assert_response :not_found
    refute_predicate quote.reload, :accepted?
  end

  test "the offer form lists gpu and cpu models in optgroups" do
    get new_trade_in_quote_path
    assert_response :success
    assert_select "h1", text: I18n.t("trade_in_quotes.new.title")
    assert_select "select#model optgroup[label=?]", I18n.t("trade_in_quotes.new.components.gpu")
    assert_select "select#model option[value=?]", "gpu:rtx4070"
    assert_select "select#model option[value=?]", "cpu:ryzen75800x3d"
  end

  test "an anonymous quote is created with the condition math and shown" do
    quote = create_quote
    assert_nil quote.user_id
    assert_equal "gpu", quote.component_type
    assert_equal "rtx4070", quote.model
    assert_predicate quote, :quoted?
    # rtx4070 base 330.00 € × 0.85 (good) = 280.50 €
    assert_equal 28_050, quote.offered_cents
    assert_in_delta (Time.current + 7.days - quote.expires_at).abs, 0, 5

    follow_redirect!
    assert_response :success
    assert_match "280.50", response.body
    # guests get a sign-in prompt instead of the accept button
    assert_match I18n.t("trade_in_quotes.show.log_in_to_accept"), response.body
  end

  test "no box trims the offer by 5%" do
    quote = create_quote(has_box: nil)
    # 33000 × 0.85 × 0.95 = 26647.5 → 26648
    assert_equal 26_648, quote.offered_cents
  end

  test "like_new with box pays the full base price" do
    quote = create_quote(model: "cpu:ryzen75800x3d", condition: "like_new")
    assert_equal TradeIns::Quote::PRICES.fetch("cpu").fetch("ryzen75800x3d").fetch("base_cents"),
                 quote.offered_cents
  end

  test "unknown model or condition re-renders the form with an alert" do
    post trade_in_quotes_path, params: { model: "gpu:unobtainium", condition: "good", has_box: "1" }
    assert_response :unprocessable_entity
    assert_match I18n.t("trade_in_quotes.create.errors.unknown_model"), response.body
    assert_equal 0, TradeIn.count

    post trade_in_quotes_path, params: { model: "gpu:rtx4070", condition: "mint", has_box: "1" }
    assert_response :unprocessable_entity
    assert_match I18n.t("trade_in_quotes.create.errors.unknown_condition"), response.body
  end

  test "guests cannot accept an offer" do
    quote = create_quote
    assert_difference -> { TradeIn.count }, 0 do
      post trade_in_quote_acceptance_path(quote)
    end
    assert_redirected_to new_session_path
    refute_predicate quote.reload, :accepted?
  end

  test "a signed-in user accepts and claims the quote" do
    quote = create_quote
    sign_in_as users(:one)
    post trade_in_quote_acceptance_path(quote)
    assert_redirected_to sell_dashboard_path
    assert_match I18n.t("trade_in_acceptances.create.accepted"), flash[:notice]

    quote.reload
    assert_predicate quote, :accepted?
    assert_equal users(:one), quote.user
  end

  test "accepting after expiry marks the quote expired" do
    quote = create_quote
    quote.update_column(:expires_at, 1.hour.ago)

    sign_in_as users(:one)
    post trade_in_quote_acceptance_path(quote)
    assert_redirected_to trade_in_quote_path(quote)
    assert_match I18n.t("trade_in_acceptances.create.expired"), flash[:alert]
    assert_predicate quote.reload, :expired?
  end

  test "an already-expired offer shows as expired on its page" do
    quote = create_quote
    quote.update_column(:expires_at, 1.day.ago)
    get trade_in_quote_path(quote)
    assert_response :success
    assert_match I18n.t("trade_in_quotes.show.expired"), response.body
    assert_predicate quote.reload, :expired?
  end

  test "another user cannot steal a claimed quote" do
    quote = create_quote
    # The quote starts anonymous, so user two may legitimately claim it...
    sign_in_as users(:two)
    post trade_in_quote_acceptance_path(quote)
    assert_redirected_to sell_dashboard_path
    assert_match I18n.t("trade_in_acceptances.create.accepted"), flash[:notice]
    assert_equal users(:two), quote.reload.user
    assert_predicate quote, :accepted?

    # ...but user one can no longer take it over afterwards.
    sign_in_as users(:one)
    post trade_in_quote_acceptance_path(quote)
    assert_match I18n.t("trade_in_acceptances.create.invalid"), flash[:alert]
    assert_equal users(:two), quote.reload.user
  end
end
