require "test_helper"

class Sell::DashboardStatsTest < ActiveSupport::TestCase
  setup do
    @seller = users(:two)
    @listing = listings(:as_new)
    @listing.update_column(:views_count, 200)
  end

  # Explicit numbers: the fixture orders hand-pick PCM-2025-000001/2, so the
  # order_number sequence would collide on first use inside tests.
  def create_order(status:, days_ago:, subtotal:, commission: 0)
    order = Order.create!(number: "PCM-TEST-#{SecureRandom.hex(8).upcase}",
                          buyer: users(:one), seller: @seller, status: status,
                          subtotal_cents: subtotal, shipping_cents: 0)
    order.update_columns(commission_cents: commission,
                         total_cents: subtotal + commission,
                         created_at: days_ago.days.ago)
    order
  end

  test "counts live and in-review listings and sums lifetime views" do
    stats = Sell::DashboardStats.new(@seller).call

    assert_equal 1, stats.live_listings          # as_new (draft and rejected excluded)
    assert_equal 0, stats.in_review
    assert_equal 200, stats.total_views
  end

  test "revenue nets out commission and ignores non-completed or stale orders" do
    create_order(status: :completed, days_ago: 5, subtotal: 30000, commission: 6000)
    create_order(status: :completed, days_ago: 45, subtotal: 99000, commission: 0)
    create_order(status: :paid, days_ago: 2, subtotal: 77000, commission: 0)

    stats = Sell::DashboardStats.new(@seller).call

    # The fixture's completed order for seller two (total 50000, no commission)
    # sits inside the window, so the only created order that counts is the
    # 5-day-old one: 36000 − 6000 = 30000.
    assert_equal 2, stats.sales_count
    assert_equal 80000, stats.revenue_cents
  end

  test "conversion is zero-safe and uses lifetime views" do
    create_order(status: :completed, days_ago: 1, subtotal: 10000)

    stats = Sell::DashboardStats.new(@seller).call
    assert_in_delta 2 / 200.0, stats.conversion_rate # fixture order + this one

    zero_views = Sell::DashboardStats.new(users(:one)).call
    assert_equal 0.0, zero_views.conversion_rate if zero_views.total_views.zero?
  end

  test "favorites received counts the window on the seller's own listings" do
    Favorite.create!(user: users(:one), listing: @listing)
    Favorite.create!(user: users(:one), listing: listings(:gigabyte))

    stats = Sell::DashboardStats.new(@seller).call
    assert_equal 1, stats.favorites_received
  end

  test "weekly chart is zero-filled for twelve ISO weeks oldest first" do
    create_order(status: :completed, days_ago: 20, subtotal: 10000)
    create_order(status: :completed, days_ago: 20, subtotal: 20000)

    stats = Sell::DashboardStats.new(@seller).call
    weeks = stats.weekly_sales

    assert_equal 12, weeks.size
    assert_equal Date.current.beginning_of_week - 11.weeks, weeks.first[:week_start]
    assert_equal Date.current.beginning_of_week, weeks.last[:week_start]
    # Three weeks back holds our two orders; the fixture order lands this week.
    assert_equal 2, weeks[-4][:count]
    assert_equal 1, weeks.last[:count]
    assert_equal 3, weeks.sum { |w| w[:count] }
    assert_equal 2, stats.weekly_max
  end

  test "needs attention surfaces rejects, pending offers and unanswered threads" do
    Offer.create!(listing: @listing, buyer: users(:one), amount_cents: 20000,
                  status: :pending, expires_at: 3.days.from_now)
    Offer.create!(listing: listings(:gigabyte), buyer: users(:two), amount_cents: 20000,
                  status: :pending, expires_at: 3.days.from_now)
    Offer.create!(listing: @listing, buyer: users(:admin), amount_cents: 25000,
                  status: :pending, expires_at: 1.day.ago) # time-expired

    conversation = Conversation.create!(listing: @listing, buyer: users(:one), seller: @seller,
                                        last_message_at: Time.current)
    Message.create!(conversation: conversation, sender: users(:one), body: "Is this available?")

    stats = Sell::DashboardStats.new(@seller).call

    assert_equal [ listings(:rejected).id ], stats.rejected_listings.ids
    assert_equal "Photos unreadable", stats.rejected_listings.first.rejection_reason
    assert_equal 1, stats.pending_offers_count
    assert_equal 1, stats.unanswered_conversations_count

    Message.create!(conversation: conversation, sender: @seller, body: "Yes!")
    assert_equal 0, Sell::DashboardStats.new(@seller).call.unanswered_conversations_count
  end

  test "top listings ranks by views, approved and sold only" do
    listings(:sold).update_column(:views_count, 500) # user one's sold listing
    @listing.update_column(:views_count, 50)
    listings(:draft).update_column(:views_count, 999)

    top = Sell::DashboardStats.new(@seller).call.top_listings
    assert_equal [ @listing.id ], top.ids
    assert_operator top.to_a.size, :<=, 5
  end
end
