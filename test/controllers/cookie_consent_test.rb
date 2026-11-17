require "test_helper"

# Phase 7b cookie banner + footer legal block. The banner renders only while
# no valid consent cookie exists; the preferences dialog is always in the DOM
# so the footer button can reopen it. Legal links appear once a deliverable
# LegalPage exists for the current country/locale.
class CookieConsentTest < ActionDispatch::IntegrationTest
  test "no consent cookie shows the banner and the always-present dialog" do
    get listings_path

    assert_response :success
    assert_select "div[data-cookie-consent-target=banner]"
    assert_select "div[data-cookie-consent-target=banner] button", text: I18n.t("cookie_consent.banner.accept")
    assert_select "dialog[data-cookie-consent-target=dialog]"
  end

  test "a valid consent cookie hides the banner but keeps the dialog" do
    set_consent(%w[necessary analytics])
    get listings_path

    assert_response :success
    assert_select "div[data-cookie-consent-target=banner]", count: 0
    assert_select "dialog[data-cookie-consent-target=dialog]"
  end

  test "a cookie from an older consent version shows the banner again" do
    cookies[:cookie_consent] = { version: 0, categories: %w[necessary analytics] }.to_json
    get listings_path

    assert_select "div[data-cookie-consent-target=banner]"
  end

  test "an unparseable consent cookie shows the banner" do
    cookies[:cookie_consent] = "not-json"
    get listings_path

    assert_select "div[data-cookie-consent-target=banner]"
  end

  test "footer links every deliverable legal page and the preferences button" do
    LegalPage.create!(country_code: "ES", locale: "es", slug: "terms",
                      title: "Términos", body: "Texto.", published: true)

    get listings_path

    assert_select "nav[aria-label='#{I18n.t('footer.legal')}'] a[href='#{legal_page_path('terms')}']",
                  text: I18n.t("legal_pages.slugs.terms")
    assert_select "button[data-action='cookie-consent#openPreferences']",
                  text: I18n.t("footer.cookie_preferences")
    assert_select "nav[aria-label='#{I18n.t('footer.legal')}'] a[href='#{legal_page_path('privacy')}']",
                  count: 0
  end

  test "footer links the Trust & Safety page" do
    get listings_path

    assert_select "a[href='#{trust_path}']", text: I18n.t("footer.trust_safety")
  end

  private

  def set_consent(categories)
    cookies[:cookie_consent] = { version: 1, categories: categories }.to_json
  end
end
