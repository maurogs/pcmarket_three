# POST /notifications_read — marks every notification of the current user
# as read (singular resource: POST creates the "read everything" action).
class NotificationsReadsController < ApplicationController
  before_action :require_authentication

  def create
    Notification.mark_all_as_read_for(current_user)
    redirect_to notifications_path, status: :see_other
  end
end
