# Sent when a GDPR data export is ready: a signed link to the attached
# JSON that stays valid for 7 days.
class DataExportMailer < ApplicationMailer
  EXPORT_LINK_TTL = 7.days

  def ready
    @user = params[:user]

    I18n.with_locale(@user.locale.presence || I18n.default_locale) do
      @export_url = rails_blob_url(@user.export, expires_in: EXPORT_LINK_TTL)
      mail to: @user.email_address, subject: t(".subject")
    end
  end
end
