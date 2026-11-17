require "test_helper"

# Phase 7c: the legal-text seed loader (db/seeds/legal_pages.rb). Templates
# live in db/seeds/legal/<COUNTRY>/<locale>/<slug>.md, upsert by
# (country, locale, slug), and an admin-approved page (needs_legal_review
# false) is never overwritten. Also checks the shipped ES/es set: all 8
# slugs, headings for the TOC, and that the identity placeholders the docs
# use resolve once the identity Settings are configured. Phase 7d: every
# country/locale folder shipped under db/seeds/legal (ES/es, ES/en, GB/en)
# must satisfy the same structural contract — complete slug set, h2
# headings, italic template note first, and no placeholder outside the set
# the renderer can resolve.
class LegalPagesSeedsTest < ActiveSupport::TestCase
  LOADER = Rails.root.join("db", "seeds", "legal_pages.rb").to_s
  LEGAL_ROOT = Rails.root.join("db", "seeds", "legal")

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

  # Phase 7d: every country/locale set shipped under db/seeds/legal must
  # satisfy the same structural contract, so a new set cannot ship half a
  # corpus or sneak in a placeholder the renderer cannot resolve.
  test "every shipped country/locale set is complete, structured and placeholder-clean" do
    allowed = Setting.legal_identity.keys

    legal_sets.each do |country_code, locale|
      set = "#{country_code}/#{locale}"
      files = Dir.glob(LEGAL_ROOT.join(country_code, locale, "*.md")).sort
                  .map { |path| File.basename(path, ".md") }
      assert_equal LegalPage::SLUGS.sort, files, "#{set} must ship exactly the eight slugs"

      pages = LegalPage.where(country_code: country_code, locale: locale).index_by(&:slug)
      assert_equal files, pages.keys.sort, "#{set} must seed exactly the eight slugs"

      pages.each_value do |page|
        assert_operator page.body.scan(/^## /).size, :>=, 4, "#{set}/#{page.slug} needs 4+ '##' headings"

        first_line = page.body.lines.first.to_s.strip
        assert_match(/\A_.+._\z/, first_line, "#{set}/#{page.slug} must open with the italic template note")

        unresolved = page.body.scan(LegalPages::Render::PLACEHOLDER).flatten.uniq - allowed
        assert_empty unresolved, "#{set}/#{page.slug} uses placeholders the renderer cannot resolve"
      end
    end
  end

  test "every shipped set renders with a 4+ entry TOC and no raw placeholders left" do
    Setting.set("site_name", "PCMarket")
    Setting.set("legal_name", "Template Test Ltd")
    Setting.set("tax_id", "GB123456789")
    Setting.set("registered_address", "1 Example Street, London")
    Setting.set("mercantile_registry_data", "Companies House 12345678")
    Setting.set("contact_email", "legal@pcmarket.example")
    Setting.set("dpo_email", "dpo@pcmarket.example")

    legal_sets.each do |country_code, locale|
      set = "#{country_code}/#{locale}"

      LegalPage.where(country_code: country_code, locale: locale).find_each do |page|
        result = LegalPages::Render.call(page)

        assert_operator result.toc.size, :>=, 4, "#{set}/#{page.slug} TOC must have 4+ entries"
        assert_no_match(/\{\{|\}\}/, result.body_html, "#{set}/#{page.slug} still has a raw {{placeholder}}")
      end
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

  # Country/locale pairs that actually ship template folders — the loader's
  # contract, read off the filesystem rather than hardcoded.
  def legal_sets
    @legal_sets ||= Dir.glob(LEGAL_ROOT.join("*", "*")).filter_map do |dir|
      next unless File.directory?(dir)

      Pathname.new(dir).relative_path_from(LEGAL_ROOT).each_filename.to_a
    end.sort
  end

  def run_loader
    load LOADER
  end

  def assert_start_with(string, prefix)
    assert string.start_with?(prefix), "expected #{string.first(40).inspect} to start with #{prefix.inspect}"
  end
end
