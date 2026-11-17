module Admin
  # Every admin controller inherits from this. Non-admins (and impersonating
  # admins — their Current.user is the non-admin target) get a 404, not a
  # 403: a forbidden response would confirm the panel exists at all.
  class BaseController < ApplicationController
    layout "admin"

    before_action :require_admin!

    private

    def require_admin!
      if Current.user&.banned?
        # Banned admins land on the sign-in page rather than a 404 so the
        # suspension is visible; sign-in then refuses them (SessionsController).
        redirect_to new_session_path, alert: t("admin.access.banned")
        return
      end
      raise ActiveRecord::RecordNotFound unless Current.user&.admin?
    end
  end
end
