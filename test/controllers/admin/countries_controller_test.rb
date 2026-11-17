require "test_helper"

# Country launch toggles (Phase 6b). The Country model refuses to flip
# `enabled` on until every LegalPage::SLUGS entry is PUBLISHED in the
# country's default locale; the 422 re-render lists the missing slugs.
class Admin::CountriesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:admin) }

  test "index lists countries and the edit page shows the launch checklist" do
    get admin_countries_path
    assert_response :ok
    assert_includes response.body, I18n.t("countries.gb")

    get edit_admin_country_path(countries(:gb))
    assert_response :ok
    missing = I18n.t("admin.countries.edit.checklist.legal_pages_missing",
                     slugs: LegalPage::SLUGS.join(", "))
    assert_includes response.body, missing
  end

  test "enabling a blocked country without published legal pages is refused and lists the missing slugs" do
    country = countries(:gb) # enabled: false, default_locale: en

    assert_no_difference "AdminAuditLog.count" do
      patch admin_country_path(country), params: { country: { enabled: "1" } }
    end
    assert_response :unprocessable_entity

    message = I18n.t("activerecord.errors.messages.missing_legal_pages",
                     slugs: LegalPage::SLUGS.join(", "))
    assert_includes response.body, message

    assert_not country.reload.enabled?, "the flag must not flip"
    LegalPage::SLUGS.each do |slug|
      assert_includes message, slug, "the error message must name the missing #{slug} page"
    end
  end

  test "published pages in another locale do not unlock the enable" do
    LegalPage::SLUGS.each do |slug|
      LegalPage.create!(country_code: "GB", locale: "es", slug: slug,
                        title: slug.titleize, body: "Texto", published: true)
    end
    country = countries(:gb) # default_locale is en, so es pages do not count

    patch admin_country_path(country), params: { country: { enabled: "1" } }
    assert_response :unprocessable_entity
    assert_not country.reload.enabled?
  end

  test "enable succeeds once every legal page is published in the default locale (audited)" do
    LegalPage::SLUGS.each do |slug|
      LegalPage.create!(country_code: "GB", locale: "en", slug: slug,
                        title: slug.titleize, body: "## Body\n\nText.", published: true)
    end
    country = countries(:gb)

    assert_difference "AdminAuditLog.count" do
      patch admin_country_path(country), params: { country: { enabled: "1" } }
    end
    assert_redirected_to admin_countries_path
    assert_not flash[:notice].blank?
    assert country.reload.enabled?

    audit = AdminAuditLog.last
    assert_equal "country_update", audit.action
    assert_equal "GB", audit.details["code"]
    assert_equal true, audit.details["enabled"]
  end

  test "unpublished legal pages do not count either" do
    LegalPage::SLUGS.each do |slug|
      LegalPage.create!(country_code: "GB", locale: "en", slug: slug,
                        title: slug.titleize, body: "Text", published: false)
    end
    country = countries(:gb)

    patch admin_country_path(country), params: { country: { enabled: "1" } }
    assert_response :unprocessable_entity
    assert_not country.reload.enabled?
  end

  test "settings edits on an already enabled country are unaffected by the legal-page gate" do
    country = countries(:es) # enabled since the seed

    assert_difference "AdminAuditLog.count" do
      patch admin_country_path(country), params: { country: { vat_rate: "19.00" } }
    end
    assert_redirected_to admin_countries_path
    assert_equal BigDecimal("19.00"), country.reload.vat_rate
  end

  test "non-admin gets 404 on every country action" do
    sign_in_as users(:one)

    get admin_countries_path
    assert_response :not_found
    get edit_admin_country_path(countries(:gb))
    assert_response :not_found
    patch admin_country_path(countries(:gb)), params: { country: { enabled: "1" } }
    assert_response :not_found
    assert_not countries(:gb).reload.enabled?
  end
end
