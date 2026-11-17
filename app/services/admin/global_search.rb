module Admin
  # Top-bar search across the three record types an admin reaches for:
  # users (e-mail/username), listings (title or numeric id) and orders
  # (number). Small fixed limits — this is a locator, not a report.
  class GlobalSearch
    LIMIT = 8

    Result = Struct.new(:users, :listings, :orders, keyword_init: true)

    def self.call(query)
      like = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"

      users = User
              .where("email_address ILIKE :q OR username ILIKE :q", q: like)
              .order(:username).limit(LIMIT)

      listings = Listing.where("title ILIKE :q", q: like).order(created_at: :desc)
      listings = listings.or(Listing.where(id: query)) if query.match?(/\A\d+\z/)

      orders = Order.where("number ILIKE :q", q: like).order(created_at: :desc).limit(LIMIT)

      Result.new(users: users, listings: listings.limit(LIMIT), orders: orders)
    end
  end
end
