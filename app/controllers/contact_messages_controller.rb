# POST /contact_messages — the contact form on /pages/contact (Phase 7b).
# Submissions are stored as ContactMessage rows (locale captured from the
# request) and an e-mail copy goes to the configured support address.
# The rate limit keeps a single client to a handful of messages per hour.
class ContactMessagesController < ApplicationController
  allow_unauthenticated_access only: :create
  rate_limit to: 5, within: 30.minutes, only: :create,
             with: -> { redirect_to page_path("contact"), alert: t(".rate_limited") }

  def create
    @message = ContactMessage.new(message_params)
    @message.locale = I18n.locale.to_s

    if @message.save
      ContactMailer.with(message: @message).received.deliver_later
      redirect_to page_path("contact"), notice: t(".created")
    else
      redirect_to page_path("contact"), alert: t(".invalid")
    end
  end

  private

  def message_params
    params.require(:contact_message).permit(:name, :email, :subject, :body)
  end
end
