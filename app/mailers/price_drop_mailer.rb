# Wishlist price-drop alert: sent when a saved listing gets cheaper. Gated
# on the recipient's email_price_drop preference inside the action, so a
# preference flip between enqueue and delivery is honoured.
class PriceDropMailer < ApplicationMailer
  def price_drop
    @user = params[:user]
    @listing = params[:listing]
    return unless @user.wants_email?("price_drop")

    @previous_cents = @listing.favorites.where(user: @user).maximum(:price_cents_at_save)

    I18n.with_locale(@user.locale.presence || I18n.default_locale) do
      mail to: @user.email_address,
           subject: t(".subject", title: @listing.title.truncate(60))
    end
  end
end
