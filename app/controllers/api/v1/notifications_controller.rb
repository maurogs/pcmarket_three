# GET /api/v1/notifications — same records as the web bell (Notification
# scope + eager loads). Marking read is its own endpoint (NotificationsReads).
class Api::V1::NotificationsController < Api::V1::BaseController
  before_action :verify_user!

  def index
    @pagy, @notifications = pagy(
      current_user.notifications.order(created_at: :desc, id: :desc)
                   .includes(offer: :listing, conversation: %i[buyer seller],
                             order: :user, listing: :user),
      limit: page_size
    )
  end
end
