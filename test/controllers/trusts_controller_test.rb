require "test_helper"

# Trust & Safety page (Phase 7b). Stats are live DB counts; anything below
# the min_public_stat threshold stays invisible — no vanity numbers, and no
# empty-looking counters either.
class TrustsControllerTest < ActionDispatch::IntegrationTest
  test "the page renders for anonymous visitors" do
    get trust_path

    assert_response :success
    assert_select "h1", I18n.t("trusts.show.hero.title")
    assert_includes response.body, I18n.t("trusts.show.faq.title")
  end

  test "stats below the threshold are hidden entirely" do
    # Fixtures hold two completed orders — way below the default floor of 50.
    assert_operator Order.completed.count, :<, Setting.get("min_public_stat", 50)

    get trust_path
    assert_response :success
    assert_does_not_contain I18n.t("trusts.show.stats.completed_orders")
    assert_does_not_contain I18n.t("trusts.show.stats.verified_sellers")
  end

  test "stats at or above the threshold show with their real counts" do
    Setting.set("min_public_stat", 1)

    get trust_path
    assert_response :success
    assert_includes response.body, I18n.t("trusts.show.stats.completed_orders")
    assert_includes response.body, "#{Order.completed.count}</dd>"
    # Verified stores are still zero in fixtures: below the (new) floor of 1?
    # 0 < 1, so that stat must stay hidden.
    assert_does_not_contain I18n.t("trusts.show.stats.verified_sellers")
  end

  test "the protection policy badge appears once a public buyer-protection page exists" do
    get trust_path
    assert_does_not_contain I18n.t("trusts.show.hero.open_policy_badge")

    LegalPage.create!(country_code: "ES", locale: "en", slug: "buyer_protection",
                      title: "Buyer protection", body: "Covered.", published: true)

    get trust_path
    assert_includes response.body, I18n.t("trusts.show.hero.open_policy_badge")
  end

  private

  def assert_does_not_contain(text)
    assert_not response.body.include?(text), "expected page NOT to contain #{text.inspect}"
  end
end
