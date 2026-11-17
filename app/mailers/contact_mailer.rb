# Copy of every contact-form submission, sent to the configured support
# address so the team sees it in the inbox too (the row itself lives in
# admin/contact_messages). Reply-To carries the sender so support can answer
# straight from the mail client.
class ContactMailer < ApplicationMailer
  def received
    @message = params[:message]
    support = Setting.get("support_email").to_s
    return if support.blank?

    mail_to_locale do
      mail to: support, reply_to: @message.email, subject: t(".subject", subject: @message.subject)
    end
  end

  private

  # Rendered in the locale the visitor filled the form in.
  def mail_to_locale(&block)
    locale = @message.locale.presence || I18n.default_locale.to_s
    I18n.with_locale(locale, &block)
  end
end
