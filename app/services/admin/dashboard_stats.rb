module Admin
  # Platform KPIs for the admin dashboard, period-windowed (7/30/90 days).
  # Everything is aggregate SQL — one query per metric, nothing loads rows
  # into Ruby. The aggregate snapshot is cached 5 minutes per period; the
  # two small lists (oldest pending, latest signups) run live so they never
  # show a just-reviewed listing.
  class DashboardStats
    PERIODS = [ 7, 30, 90 ].freeze

    # paid and beyond, excluding the money-back states.
    GMV_STATUSES = %w[paid shipped delivered completed disputed].freeze

    Result = Struct.new(:new_users, :new_listings, :pending_count, :oldest_pending_at,
                        :approved_count, :rejected_count, :orders_count, :gmv_cents,
                        :commission_cents, :open_disputes, :active_sellers, :daily,
                        :legal_pages_pending_review,
                        keyword_init: true) do
      def daily_max
        daily.map { |day| [ day[:listings], day[:users] ].max }.max || 0
      end

      def review_total
        approved_count + rejected_count
      end

      def approval_rate
        return 0.0 if review_total.zero?

        approved_count.fdiv(review_total)
      end
    end

    def self.call(days:)
      days = PERIODS.include?(days.to_i) ? days.to_i : 30
      Rails.cache.fetch("admin/dashboard_stats/#{days}", expires_in: 5.minutes) do
        new(days: days).call
      end
    end

    # Uncached list previews for the controller (see the header comment).
    def self.oldest_pending_listings(limit: 8)
      Listing.where(status: :pending_review).order(:created_at, :id).limit(limit)
    end

    def self.latest_signups(limit: 8)
      User.order(created_at: :desc, id: :desc).limit(limit)
    end

    def initialize(days:)
      @days = PERIODS.include?(days.to_i) ? days.to_i : 30
    end

    def call
      since = @days.days.ago

      Result.new(
        new_users: User.where(created_at: since..).count,
        new_listings: Listing.where(created_at: since..).count,
        pending_count: pending_relation.count,
        oldest_pending_at: pending_relation.minimum(:created_at),
        approved_count: moderation_decision_count(ModerationEvent.approved, since),
        rejected_count: moderation_decision_count(ModerationEvent.rejected, since),
        orders_count: Order.where(created_at: since..).count,
        gmv_cents: paid_orders(since).sum(:total_cents).to_i,
        commission_cents: paid_orders(since).sum(:commission_cents).to_i,
        open_disputes: Order.disputed.count,
        active_sellers: Listing.where(created_at: since..).distinct.count(:user_id),
        daily: daily_series(since),
        legal_pages_pending_review: LegalPage.pending_legal_review.count
      )
    end

    private

    def pending_relation
      Listing.where(status: :pending_review)
    end

    def paid_orders(since)
      Order.where(status: GMV_STATUSES, created_at: since..)
    end

    # GROUP BY action inside the window: approved/rejected moderation counts
    # (the decision happened then, wherever the listing sits today).
    def moderation_decision_count(scope, since)
      scope.where(created_at: since..).count
    end

    # [{ date: Date, listings: n, users: n }, …] oldest → newest, zero-filled.
    def daily_series(since)
      listings = group_by_day(Listing.where(created_at: since..))
      users = group_by_day(User.where(created_at: since..))

      (0...@days).map do |offset|
        date = (offset - (@days - 1)).days.from_now.to_date
        {
          date: date,
          listings: listings.fetch(date, 0),
          users: users.fetch(date, 0)
        }
      end
    end

    def group_by_day(relation)
      relation.group("date_trunc('day', #{relation.table_name}.created_at)")
              .count
              .transform_keys { |time| time.in_time_zone.to_date }
    end
  end
end
