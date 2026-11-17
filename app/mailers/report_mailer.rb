# Admin-side e-mails (Phase 7b): when a listing collects Report::FLOOD_THRESHOLD
# open reports it returns to the moderation queue and every admin gets this
# heads-up, rendered in their own locale.
class ReportMailer < ApplicationMailer
  def listing_flagged
    @listing = params[:listing]
    @recipient = params[:recipient]
    @reports = @listing.reports.open.count

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
