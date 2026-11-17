require "test_helper"

class Admin::LegalPagesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:admin) }

  test "index lists existing legal pages" do
    page = legal_page(title: "Terms of Service")
    get admin_legal_pages_path
    assert_response :success
    assert_match page.title, response.body
    assert_match page.slug, response.body
  end

  test "show, new and edit render for admins" do
    page = legal_page
    get admin_legal_page_path(page)
    assert_response :success
    get new_admin_legal_page_path
    assert_response :success
    get edit_admin_legal_page_path(page)
    assert_response :success
  end

  test "non-admins get 404 everywhere under legal_pages" do
    page = legal_page
    sign_in_as users(:one)

    get admin_legal_pages_path
    assert_response :not_found
    get admin_legal_page_path(page)
    assert_response :not_found
    get new_admin_legal_page_path
    assert_response :not_found
    get edit_admin_legal_page_path(page)
    assert_response :not_found
    assert_no_difference "LegalPage.count" do
      post admin_legal_pages_path, params: { legal_page: { slug: "terms", title: "Sneaky", body: "nope" } }
    end
    assert_response :not_found
  end

  test "create persists the markdown body (audited) and show renders it as html" do
    assert_difference [ -> { LegalPage.count }, -> { AdminAuditLog.count } ] do
      post admin_legal_pages_path, params: {
        legal_page: { country_code: "ES", locale: "en", slug: "privacy",
                      title: "Privacy Policy", published: "1",
                      body: "## Title\n\nSome **bold** text.\n" }
      }
    end
    assert_redirected_to admin_legal_pages_path

    page = LegalPage.find_by!(country_code: "ES", locale: "en", slug: "privacy")
    assert_equal "## Title\n\nSome **bold** text.\n", page.body
    assert_equal "legal_page_create", AdminAuditLog.last.action
    assert_equal page, AdminAuditLog.last.subject

    get admin_legal_page_path(page)
    assert_response :success
    assert_match "<h2>Title</h2>", response.body
    assert_match "<strong>bold</strong>", response.body
  end

  test "show sanitizes hostile markdown: no scripts, handlers or javascript hrefs" do
    page = legal_page(body: <<~MD)
      ## Safe

      <script>alert(1)</script>

      <img src=x onerror=alert(1)>

      [link](javascript:alert(1))

      **bold survives**
    MD

    get admin_legal_page_path(page)
    assert_response :success

    rendered = response.body[%r{<div class="prose prose-sm max-w-none">(.*?)</div>}m, 1]
    assert rendered, "expected the rendered-markdown section on show"
    assert_no_match %r{<script}, rendered
    assert_no_match(/onerror/i, rendered)
    assert_no_match(/javascript:/, rendered)
    assert_no_match(/<img/i, rendered)
    # Ordinary markdown survives the sanitizer allowlist.
    assert_match "<strong>bold survives</strong>", rendered
    assert_match "<h2>Safe</h2>", rendered
    assert_match ">link</a>", rendered
    # And the payload never leaks anywhere else in the page.
    assert_not_includes response.body, "alert(1)"
    assert_not_includes response.body, "javascript:alert"
  end

  test "new prefills from a copy source locale (country_code/locale/slug params)" do
    source = legal_page(country_code: "ES", locale: "en", slug: "terms",
                        title: "Source Terms Title", body: "Source body text for copy")

    get new_admin_legal_page_path(country_code: "ES", locale: "en", slug: "terms")
    assert_response :success
    assert_includes response.body, "Source Terms Title"
    assert_includes response.body, "Source body text for copy"
    assert source.reload.persisted? # prefill must not touch the source row
  end

  test "creating from a copy source persists a new page for the target locale with the copied body, audited" do
    source = legal_page(country_code: "ES", locale: "en", slug: "terms",
                        title: "Source Terms Title", body: "Copied legal body")

    assert_difference [ -> { LegalPage.count }, -> { AdminAuditLog.count } ] do
      post admin_legal_pages_path, params: {
        legal_page: { country_code: "ES", locale: "fr", slug: "terms",
                      title: source.title, body: source.body, published: "0" }
      }
    end
    assert_redirected_to admin_legal_pages_path

    copy = LegalPage.find_by!(country_code: "ES", locale: "fr", slug: "terms")
    assert_equal source.body, copy.body
    assert_equal source.title, copy.title
    assert_equal "legal_page_create", AdminAuditLog.last.action
    assert_equal copy, AdminAuditLog.last.subject
    assert_equal({ "country_code" => "ES", "locale" => "fr", "slug" => "terms" },
                 AdminAuditLog.last.details)
    assert source.reload.persisted?
  end

  private

  def legal_page(country_code: "ES", locale: "en", slug: "terms",
                 title: "Legal Terms", body: "Legal body text", published: true)
    LegalPage.create!(country_code: country_code, locale: locale, slug: slug,
                      title: title, body: body, published: published)
  end
end
