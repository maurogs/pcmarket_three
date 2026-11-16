module Sell
  class BaseController < ApplicationController
    before_action :redirect_banned_users

    private

    # The rest of the app reaches the signed-in user through Current.user;
    # the sell controllers read better with the classic name.
    def current_user
      Current.user
    end
    helper_method :current_user

    # Banned sellers keep browsing (their listings are already hidden by
    # moderation) but cannot manage the sell area.
    def redirect_banned_users
      return unless Current.user&.banned?

      redirect_to root_path, alert: t("sell.banned_alert")
    end
  end
end
