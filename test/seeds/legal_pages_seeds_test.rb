require "test_helper"

# Phase 7c: the legal-text seed loader (db/seeds/legal_pages.rb). Templates
# live in db/seeds/legal/<COUNTRY>/<locale>/<slug>.md, upsert by
# (country, locale, slug), and an admin-approved page (needs_legal_review
# false) is never overwritten. Also checks the shipped ES/es set: all 8
# slugs, headings for the TOC, and that the identity placeholders the docs
# use resolve once the identity Settings are configured.
class LegalPagesSeedsTest < ActiveSupport::TestCase
  LOADER = Rails.root.join("db", "seeds", "legal_pages.rb").to_s

  setup { run_loader }

  test "seeds all eight Spanish templates for ES/es, published and pending review" do
    pages = LegalPage.where(country_code: "ES", locale: "es").index_by(&:slug)

    assert_equal LegalPage::SLUGS, pages.keys.sort_by { |slug| LegalPage::SLUGS.index(slug) }
    pages.each_value do |page|
      assert_predicate page, :published?
      assert page.needs_legal_review?, "#{page.slug} must start pending legal review"
    end
  end

  test "title comes from the first '# Title' line and the body follows it" do
    page = LegalPage.find_by!(country_code: "ES", locale: "es", slug: "terms")

    assert_equal "Condiciones generales de uso", page.title
    assert_not_includes page.body, "# Condiciones generales de uso"
    assert_start_with page.body, "_Este texto es una plantilla"
  end

  test "idempotent: a second run creates nothing and changes nothing" do
    before = LegalPage.order(:id).pluck(:title, :body, :published, :needs_legal_review)

    assert_no_difference -> { LegalPage.count } do
      run_loader
    end

    assert_equal before, LegalPage.order(:id).pluck(:title, :body, :published, :needs_legal_review)
  end

  test "never overwrites a page reviewed by legal counsel — the admin text wins" do
    reviewed = LegalPage.find_by!(country_code: "ES", locale: "es", slug: "terms")
    reviewed.update!(title: "Condiciones revisadas por el abogado",
                     body: "Texto aprobado y editado desde el panel de administración.",
                     needs_legal_review: false)

    run_loader
    run_loader # twice: the guard must hold across re-runs

    reviewed.reload
    assert_equal "Condiciones revisadas por el abogado", reviewed.title
    assert_equal "Texto aprobado y editado desde el panel de administración.", reviewed.body
    assert_not reviewed.needs_legal_review
  end

  test "every ES/es template has at least four h2 headings for the table of contents" do
    LegalPage.where(country_code: "ES", locale: "es").find_each do |page|
      assert_operator page.body.scan(/^## /).size, :>=, 4, "#{page.slug} needs 4+ '##' headings"
      toc = LegalPages::Render.call(page).toc
      assert_operator toc.size, :>=, 4, "#{page.slug} TOC must have 4+ entries"
    end
  end

  test "rendering with configured identity settings leaves no unresolved placeholder" do
    Setting.set("site_name", "PCMarket")
    Setting.set("legal_name", "PC Market Iberia, S.L.")
    Setting.set("tax_id", "B12345678")
    Setting.set("registered_address", "Calle Ejemplo 1, Madrid")
    Setting.set("mercantile_registry_data", "Registro Mercantil de Madrid, hoja M-1")
    Setting.set("contact_email", "legal@pcmarket.example")
    Setting.set("dpo_email", "dpo@pcmarket.example")

    LegalPage.where(country_code: "ES", locale: "es").find_each do |page|
      html = LegalPages::Render.call(page).body_html

      assert_no_match(/\{\{/, html, "#{page.slug} still has a raw {{placeholder}}")
      assert_no_match(/\}\}/, html, "#{page.slug} still has a raw placeholder tail")
    end
  end

  private

  def run_loader
    load LOADER
  end

  def assert_start_with(string, prefix)
    assert string.start_with?(prefix), "expected #{string.first(40).inspect} to start with #{prefix.inspect}"
  end
end
