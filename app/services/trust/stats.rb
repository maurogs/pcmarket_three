module Trust
  # Live counts for the Trust & Safety page (Phase 7b). Each stat is only
  # shown once the marketplace has enough volume for it to be meaningful —
  # below Setting "min_public_stat" (default 50) the stat is hidden.
  class Stats
    # [key, value] pairs in display order; keys map to trust.show.stats.*
    def self.visible
      threshold = Setting.get("min_public_stat", 50).to_i
      candidates = [
        [ :completed_orders, Order.completed.count ],
        [ :verified_sellers, Store.verified.joins(:user).where(user: { banned_at: nil }).count ],
        [ :reviewed_listings, ModerationEvent.where(action: %w[approved rejected]).distinct.count(:listing_id) ]
      ]
      candidates.filter_map { |key, value| [ key, value ] if value >= threshold }
    end
  end
end
