# POST /conversations/:conversation_id/messages — the only write path into a
# thread (business rules live in Messages::Send). Outsiders 404: the thread
# is looked up through Conversation.for_user before anything else. The
# default Rails.cache store (solid_cache in production, so the counter is
# shared across Puma workers) keeps spammy senders to 30 messages/minute
# per user (tests clear Rails.cache in setup where needed; in the test env
# the null store means the throttle never fires).
class MessagesController < ApplicationController
  rate_limit to: 30, within: 1.minute, only: :create,
             by: -> { Current.user.id }

  before_action :set_conversation

  def create
    result = Messages::Send.call(
      conversation: @conversation, sender: current_user,
      body: params.dig(:message, :body)
    )

    if result.message
      respond_to do |format|
        format.turbo_stream do
          # The bubble itself arrives via the model's Turbo broadcast; here
          # we just clear the composer.
          render turbo_stream: [
            turbo_stream.update("message_body", ""),
            turbo_stream.update("message_form_error", "")
          ]
        end
        format.html { redirect_to conversation_path(@conversation) }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("message_form_error", send_error_message(result.error)),
                 status: :unprocessable_entity
        end
        format.html do
          redirect_to conversation_path(@conversation), alert: send_error_message(result.error)
        end
      end
    end
  end

  private

  def set_conversation
    @conversation = Conversation.for_user(current_user).find(params[:conversation_id])
  end

  def send_error_message(error)
    t(".errors.#{error}")
  end
end
