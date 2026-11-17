module Api
  module V1
    module Sell
      # Native seller dashboard counters. Counts come straight from grouped
      # queries (Listing.status_counts, sales grouped by status) and revenue
      # reuses Sell::DashboardStats — the same number the web KPI tile shows
      # (net revenue of completed sales within its window).
      class DashboardsController < BaseController
        before_action :verify_user!

        def show
          @listing_counts = Listing.status_counts(current_user.listings)
          @published_count = @listing_counts.fetch("approved", 0) + @listing_counts.fetch("reserved", 0)
          @sold_count = @listing_counts.fetch("sold", 0)
          # Leading :: — inside Api::V1::Sell a bare `Sell::` resolves to this
          # namespace's own Sell module, not the top-level service one.
          @stats = ::Sell::DashboardStats.new(current_user).call
          @order_counts = current_user.sales.group(:status).count
          @unread_conversations = Conversation.unread_badge_count_for(current_user)
          @offers_received = Offer.pending_for_seller(current_user).count
          @store = current_user.store
        end
      end
    end
  end
end
