# Saved-search e-mails: `match_found` is the instant alert (search has
# email_alerts on), `digest` is the hourly catch-up of what the alerts
# skipped. Both gated on the email_saved_search preference in-action.
class SavedSearchMailer < ApplicationMailer
  def match_found
    @user = params[:user]
    @listing = params[:listing]
    return unless @user.wants_email?("saved_search")

    I18n.with_locale(@user.locale.presence || I18n.default_locale) do
      mail to: @user.email_address,
           subject: t(".subject", count: 1, name: @listing.title.truncate(60))
    end
  end

  def digest
    @user = params[:user]
    @listings = params[:listings]
    return unless @user.wants_email?("saved_search")

    I18n.with_locale(@user.locale.presence || I18n.default_locale) do
      mail to: @user.email_address, subject: t(".subject", count: @listings.size)
    end
  end
end
