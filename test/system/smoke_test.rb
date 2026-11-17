require "application_system_test_case"

# Smoke tests over the public storefront (no login): the header search, a
# published listing page and the footer language switch. UI strings are read
# from the locale files via I18n.t with an explicit locale, so copy changes
# never break these tests. The locale is pinned in the URL (the test suite
# sets I18n.default_locale = :en, see test/test_helper.rb).
class SmokeTest < ApplicationSystemTestCase
  setup do
    @listing = listings(:gigabyte)
  end

  test "home page renders the header search in Spanish" do
    visit root_path(locale: :es)

    assert_field I18n.t("nav.search_placeholder", locale: :es)
    assert_button I18n.t("nav.search_submit", locale: :es)
  end

  test "searching from the header navigates to the results page" do
    visit root_path(locale: :es)

    # match: :first skips the duplicate search field inside the hidden
    # mobile menu panel (translated off-screen, so still "visible").
    fill_in "q", with: "RTX", match: :first
    click_on I18n.t("nav.search_submit", locale: :es), match: :first

    assert_current_path(/listings/)
    assert_text @listing.title
  end

  test "a published listing page shows its title and price" do
    visit listing_path(@listing, locale: :es)

    assert_text @listing.title
    assert_text I18n.with_locale(:es) { ApplicationController.helpers.money(@listing.price_cents, @listing.currency) }
  end

  test "switching language in the footer shows English UI" do
    visit root_path(locale: :es)

    # Dismiss the cookie banner first: it is fixed to the bottom and can
    # intercept clicks on the footer links.
    click_on I18n.t("cookie_consent.banner.accept", locale: :es)
    click_on I18n.t("locales.en", locale: :es)

    assert_button I18n.t("nav.search_submit", locale: :en)
    assert_field I18n.t("nav.search_placeholder", locale: :en)
  end
end
