# The notification centre (Phase 5). Notifications carry their context in
# the jsonb payload (listing_id / order_id / conversation_id), rendered by
# NotificationsHelper into title + target link.
class NotificationsController < ApplicationController
  before_action :require_authentication

  def index
    @pagy, @notifications = pagy(current_user.notifications.recent)
    Notification.clear_unread_cache(current_user)
  end
end
