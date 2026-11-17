# POST /api/v1/notifications/read_all — bulk-marks every notification read
# (same update as the web bell's "Mark all read" plus the badge-cache clear).
class Api::V1::NotificationsReadsController < Api::V1::BaseController
  before_action :verify_user!

  def create
    current_user.notifications.where(read: false).update_all(read: true, updated_at: Time.current)
    Notification.clear_unread_cache(current_user)
    render json: { message: t("api.notifications.read_all"), unread: 0 }
  end
end
