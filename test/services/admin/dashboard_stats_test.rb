require "test_helper"

class Admin::DashboardStatsTest < ActiveSupport::TestCase
  setup { Rails.cache.clear }

  test "period window only counts recent activity" do
    old = listings(:pending)
    old.update_columns(created_at: 40.days.ago)

    result = Admin::DashboardStats.call(days: 30)
    assert_equal Listing.count - 1, result.new_listings

    all = Admin::DashboardStats.call(days: 90)
    assert_equal Listing.count, all.new_listings
  end

  test "pending backlog is measured regardless of age" do
    stats = Admin::DashboardStats.call(days: 7)
    assert_equal Listing.where(status: :pending_review).count, stats.pending_count
    assert_not_nil stats.oldest_pending_at
  end

  test "approval rate comes from moderation events in the window" do
    listing = listings(:pending)
    rejected = listings(:draft)
    rejected.submit_for_review! # only pending_review listings can be rejected
    Moderations::Approve.call(listing, admin: users(:admin))
    Moderations::Reject.call(rejected, reason_key: "other", note: nil,
                             admin: users(:admin))

    stats = Admin::DashboardStats.call(days: 7)
    assert_equal 1, stats.approved_count
    assert_equal 1, stats.rejected_count
    assert_in_delta 0.5, stats.approval_rate, 0.001
  end

  test "daily series has one bucket per day with a max" do
    stats = Admin::DashboardStats.call(days: 7)
    assert_equal 7, stats.daily.size
    assert stats.daily.all? { |d| d.key?(:listings) && d.key?(:users) }
    assert_operator stats.daily_max, :>=, 0
  end

  test "pending legal review counts published pages only" do
    LegalPage.create!(country_code: "ES", locale: "es", slug: "terms",
                      title: "T", body: "b", published: true) # needs_legal_review defaults true
    LegalPage.create!(country_code: "ES", locale: "es", slug: "privacy",
                      title: "P", body: "b", published: true, needs_legal_review: false)
    LegalPage.create!(country_code: "ES", locale: "es", slug: "cookies",
                      title: "C", body: "b", published: false)

    stats = Admin::DashboardStats.call(days: 7)
    assert_equal 1, stats.legal_pages_pending_review
  end

  test "results are cached per period" do
    first = Admin::DashboardStats.call(days: 30)
    User.create!(email_address: "fresh-#{SecureRandom.hex(4)}@example.com",
                 password: "password1234", password_confirmation: "password1234",
                 username: "fresh#{SecureRandom.hex(3)}", first_name: "F", last_name: "G")

    cached = Admin::DashboardStats.call(days: 30)
    assert_equal first.new_users, cached.new_users

    Rails.cache.clear
    assert_operator Admin::DashboardStats.call(days: 30).new_users, :>, cached.new_users
  end
end
