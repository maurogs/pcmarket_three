# Moderation outcome e-mails (Phase 6a): approved / rejected. The rejection
# body carries the reason_text the moderator chose (translated label +
# optional note), so the seller sees exactly what the dashboard shows.
class ModerationMailer < ApplicationMailer
  def approved
    @listing = params[:listing]
    @recipient = params[:recipient]

    mail_to_locale do
      mail to: @recipient.email_address, subject: t(".subject", title: @listing.title)
    end
  end

  def rejected
    @listing = params[:listing]
    @recipient = params[:recipient]

    mail_to_locale do
      mail to: @recipient.email_address, subject: t(".subject", title: @listing.title)
    end
  end

  private

  def mail_to_locale(&block)
    locale = @recipient.locale.presence || I18n.default_locale.to_s
    I18n.with_locale(locale, &block)
  end
end
