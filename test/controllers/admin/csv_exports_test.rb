require "test_helper"

# Phase 6b CSV exports (admin listings index + newsletter subscribers) go
# through CsvBuilder, which guards seller-/user-controlled cells that would
# otherwise execute as spreadsheet formulas (=, +, -, @, TAB, CR -> leading ').
class Admin::CsvExportsTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:admin) }

  test "admin listings csv export is an attachment with guarded formula titles" do
    evil_title = "=CMD|' /C calc'!A0"
    evil = Listing.create!(user: users(:one), store: stores(:one), category: categories(:gpus),
                           title: evil_title, price_cents: 1000, condition: "used_good",
                           status: "pending_review", quantity: 1,
                           description: "Formula injection probe")

    get admin_listings_path(format: :csv)
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match /attachment; filename="pcmarket-listings-#{Date.current}\.csv"/,
                 response.headers["Content-Disposition"]

    assert_includes response.body, "#{evil.id},'#{evil_title},pending_review,"
    assert_not_includes response.body, ",#{evil_title},"
    # Ordinary seller text passes through untouched.
    assert_includes response.body, ",Gigabyte RTX 4070 Gaming OC,approved,"
  end

  test "admin listings csv export honors the index filters" do
    get admin_listings_path(format: :csv, status: "approved")
    assert_response :success
    assert_includes response.body, listings(:gigabyte).title
    assert_not_includes response.body, listings(:pending).title
  end

  test "newsletter subscribers csv export guards formula-prefixed emails" do
    evil = NewsletterSubscription.create!(email: "=payload@example.com", locale: "en")
    safe = NewsletterSubscription.create!(email: "safe-subscriber@example.com", locale: "en")

    get admin_newsletter_subscriptions_path(format: :csv)
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match /attachment; filename="pcmarket-newsletter-#{Date.current}\.csv"/,
                 response.headers["Content-Disposition"]

    assert_includes response.body, "#{evil.id},'#{evil.email},en,"
    assert_not_includes response.body, ",#{evil.email},"
    assert_includes response.body, "#{safe.id},#{safe.email},en,"
  end

  test "newsletter csv export honors the search filter" do
    NewsletterSubscription.create!(email: "needle@example.com", locale: "en")
    NewsletterSubscription.create!(email: "haystack@example.com", locale: "en")

    get admin_newsletter_subscriptions_path(format: :csv, q: "needle")
    assert_response :success
    assert_includes response.body, "needle@example.com"
    assert_not_includes response.body, "haystack@example.com"
  end
end
