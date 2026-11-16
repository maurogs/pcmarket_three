# Aggregated seller-dashboard numbers, one query per metric — nothing loads
# full result sets into Ruby. KPI framing:
#
#   * live_listings / in_review / total_views are *current* figures
#     (views_count is a lifetime counter column, so views cannot be windowed);
#   * favorites_received, sales_count and revenue_cents cover the last
#     WINDOW (30 days);
#   * conversion_rate = sales_count / total_views, zero-guarded.
#
# weekly_sales is zero-filled for the last CHART_WEEKS ISO weeks (oldest
# first) from a single GROUP BY date_trunc query.
module Sell
  class DashboardStats
    WINDOW = 30.days.freeze
    CHART_WEEKS = 12

    Result = Struct.new(:live_listings, :in_review, :total_views, :favorites_received,
                        :sales_count, :revenue_cents, :conversion_rate,
                        :weekly_sales, :top_listings,
                        :rejected_listings, :pending_offers, :pending_offers_count,
                        :unanswered_conversations_count, keyword_init: true) do
      def weekly_max
        weekly_sales.map { |week| week[:count] }.max || 0
      end
    end

    def initialize(user)
      @user = user
    end

    def call
      window_start = WINDOW.ago
      sales = completed_sales(window_start)
      sales_count = sales.count
      views = seller_listings.sum(:views_count).to_i

      Result.new(
        live_listings: seller_listings.where(status: :approved).count,
        in_review: seller_listings.where(status: :pending_review).count,
        total_views: views,
        favorites_received: favorites_received(window_start),
        sales_count: sales_count,
        revenue_cents: sales.sum(Arel.sql("total_cents - commission_cents")).to_i,
        conversion_rate: conversion_rate(sales_count, views),
        weekly_sales: weekly_sales,
        top_listings: top_listings,
        rejected_listings: rejected_listings,
        pending_offers: pending_offers,
        pending_offers_count: Offer.pending_for_seller(@user).count,
        unanswered_conversations_count: Conversation.unanswered_for_seller(@user).count
      )
    end

    private

    def seller_listings
      Listing.where(user_id: @user.id)
    end

    def completed_sales(window_start)
      Order.where(seller_id: @user.id, status: :completed, created_at: window_start..)
    end

    # Favorites on the seller's own listings created inside the window.
    def favorites_received(window_start)
      Favorite.where(listing_id: seller_listings.select(:id), created_at: window_start..).count
    end

    # Views are lifetime counters, so the ratio is an approximation kept
    # deliberately simple — and division-free when nobody has viewed anything.
    def conversion_rate(sales_count, views)
      return 0.0 if views.zero?

      sales_count.fdiv(views)
    end

    # [{ week_start: Date (Monday), count: Integer }, …] oldest → newest.
    def weekly_sales
      first_week = Date.current.beginning_of_week - ((CHART_WEEKS - 1) * 7).days
      counts = Order.where(seller_id: @user.id, status: :completed, created_at: first_week..)
                    .group("date_trunc('week', orders.created_at)")
                    .count
                    .transform_keys { |time| time.in_time_zone.to_date }

      (0...CHART_WEEKS).map do |week|
        week_start = first_week + (week * 7).days
        { week_start: week_start, count: counts.fetch(week_start, 0) }
      end
    end

    # Top five by lifetime views; ORDER BY … LIMIT keeps it server-side.
    def top_listings
      seller_listings.where(status: [ :approved, :sold ])
                     .order(views_count: :desc, id: :desc)
                     .limit(5)
    end

    # Small previews for "Needs attention"; the true pending-offer count is
    # separate so the copy can say "4 offers" while listing only three.
    def rejected_listings
      Listing.recently_rejected_for(@user).limit(3)
    end

    def pending_offers
      Offer.pending_for_seller(@user).order(created_at: :desc, id: :desc).limit(3)
    end
  end
end
