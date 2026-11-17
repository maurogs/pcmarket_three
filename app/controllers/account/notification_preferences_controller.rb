module Account
  # Email notification preferences (checkbox matrix saved as JSONB).
  class NotificationPreferencesController < BaseController
    def show
    end

    def update
      current_user.update_notification_preferences(notification_params)
      redirect_to account_notification_preferences_path, notice: t(".updated")
    end

    private

    def notification_params
      # Unchecked checkboxes post nothing, so the form's hidden blanks plus
      # the ticked values combine into "0"/"1" per key.
      params.require(:user).permit(:email_new_message, :email_offers, :email_orders,
                                   :email_price_drop, :email_saved_search, :email_newsletter)
                                   .to_h.symbolize_keys
    end
  end
end
