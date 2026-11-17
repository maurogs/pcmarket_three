require "test_helper"

# Public legal-page delivery (Phase 7b): whitelist of slugs, the
# (country, locale) → en → country-default fallback chain, TOC anchors and
# HTML-escaped {{placeholder}} substitution from Settings.
class LegalPagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @terms = LegalPage.create!(country_code: "ES", locale: "en", slug: "terms",
                               title: "Terms & conditions",
                               body: "Company: {{legal_name}}\n\n## Liability\n\nPlain.\n\n## Refunds\n\n{{unknown_key}} stays.",
                               published: true)
  end

  test "an exact (country, locale) match is served with TOC anchors" do
    get legal_page_path("terms")

    assert_response :success
    assert_includes response.body, "Liability"
    assert_includes response.body, 'id="sec-1"'
    assert_includes response.body, I18n.t("legal_pages.show.toc_title")
    assert_not_includes response.body, "not available in your language"
  end

  test "a missing exact locale falls back to English with a visible notice" do
    # Country ES, reader locale :es — only the :en page exists.
    get legal_page_path("terms", locale: :es)

    assert_response :success
    expected = I18n.with_locale(:es) { I18n.t("legal_pages.show.fallback_notice", locale_name: I18n.t("locales.en")) }
    assert_includes response.body, expected
    assert_includes response.body, "Liability" # English body is still rendered
  end

  test "company placeholders are substituted with escaped Settings values" do
    Setting.set("legal_name", "Fiktek <b>S.L.</b>")

    get legal_page_path("terms")

    assert_includes response.body, "Fiktek &lt;b&gt;S.L.&lt;/b&gt;"
    assert_not_includes response.body, "Fiktek <b>S.L.</b>"
    # Unknown placeholders are left verbatim, never silently emptied.
    assert_includes response.body, "{{unknown_key}}"
  end

  test "unpublished pages and unknown slugs are 404" do
    @terms.update!(published: false)
    get legal_page_path("terms")
    assert_response :not_found

    @terms.update!(published: true)
    get legal_page_path("quantum-teleporty")
    assert_response :not_found
  end

  test "a country with no published page at all is 404" do
    # ES/en exists, but the GB country (disabled → not the current one). The
    # current country (ES) with a slug nobody published is also 404.
    get legal_page_path("privacy")
    assert_response :not_found
  end

  test "the country default locale is the last link of the chain" do
    @terms.update!(locale: "es") # only the ES default-locale page exists

    get legal_page_path("terms") # reader locale :en → falls through to ES default (es)
    assert_response :success
    expected = I18n.t("legal_pages.show.fallback_notice", locale_name: I18n.t("locales.es"))
    assert_includes response.body, expected
  end
end
