module Api
  module V1
    # GET /api/v1/me — the token owner's profile plus the three header badges
    # (unread threads, unread notifications, cart size) native apps show.
    # The badge helpers are the same cached counters the web header uses.
    class MeController < BaseController
      def show
        user = Current.user
        @unread_conversations = Conversation.unread_badge_count_for(user)
        @unread_notifications = Notification.unread_count_for(user)
        @cart_items = Cart.for_user(user).cart_items.sum(:quantity)
      end
    end
  end
end
