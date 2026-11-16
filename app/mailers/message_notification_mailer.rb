# E-mail heads-up for unread chat mail. Only enqueued by Messages::Send when
# the recipient has no unread "new_message" notification for the thread in
# the last 15 minutes (anti-spam throttle).
class MessageNotificationMailer < ApplicationMailer
  def new_message
    @recipient = params[:recipient]
    @message = params[:message]
    @conversation = @message.conversation

    locale = @recipient.locale.presence || I18n.default_locale.to_s
    I18n.with_locale(locale) do
      mail to: @recipient.email_address,
           subject: t(".subject", sender: @message.sender.display_name)
    end
  end
end
