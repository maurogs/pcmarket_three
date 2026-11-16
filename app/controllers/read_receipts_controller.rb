# Explicit read-receipt endpoint: marking happens automatically when the
# thread is opened (ConversationsController#show); this POST lets a client
# re-sync receipts and re-renders the header badge in place. Scoping is the
# same for_user lookup — a foreign conversation id 404s.
class ReadReceiptsController < ApplicationController
  def create
    conversation = Conversation.for_user(current_user).find(params[:conversation_id])
    conversation.mark_messages_read_for(current_user)
    Conversation.clear_unread_cache(current_user)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "unread-conversations-badge",
          partial: "shared/unread_conversations_badge", locals: { user: current_user }
        )
      end
      format.html { redirect_to conversation_path(conversation) }
    end
  end
end
