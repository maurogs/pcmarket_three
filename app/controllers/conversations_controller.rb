# Internal chat inbox and thread pages (Phase 4a). Auth required (no
# allow_unauthenticated_access anywhere below); every lookup goes through
# Conversation.for_user, so another user's thread 404s regardless of the id
# handed to us.
class ConversationsController < ApplicationController
  before_action :set_conversation, only: :show

  # "Chats" tab of the inbox. Rows + last-message previews for the page come
  # from a handful of queries: paginated conversations with the parties and
  # listing photos loaded, one grouped unread count.
  def index
    @pagy, @conversations = pagy(
      Conversation.for_user(current_user).recent
                  .includes(:buyer, :seller, listing: { photos_attachments: :blob }),
      limit: 20
    )
    @unread_counts = Conversation.unread_counts_by_conversation_for(current_user, @conversations)
  end

  # Two-pane thread. Opening it marks the other party's messages read (one
  # UPDATE) before counts are computed, so the sidebar badges are fresh.
  def show
    @conversation.mark_messages_read_for(current_user)
    Conversation.clear_unread_cache(current_user)

    @messages = @conversation.messages.order(:created_at, :id).includes(:sender, offer: :listing)
    @safety_flagged = @messages.any?(&:safety_flagged?)

    @inbox = Conversation.for_user(current_user).recent
                         .excluding(@conversation)
                         .includes(:buyer, :seller, listing: { photos_attachments: :blob })
                         .limit(10)
    @unread_counts = Conversation.unread_counts_by_conversation_for(current_user, @inbox)
  end

  # "Message seller" on the listing page. The listing itself must be visible
  # to the requester — hidden ones 404, same rule as ListingsController#show.
  def create
    listing = Listing.friendly.find(params[:listing_id])
    unless listing.approved? || listing.reserved? || listing.user_id == current_user.id || current_user.admin?
      raise ActiveRecord::RecordNotFound
    end

    result = Conversations::Start.call(user: current_user, listing: listing)

    case result.error
    when nil then redirect_to conversation_path(result.conversation)
    when :self then redirect_to listing_path(listing), alert: t(".self")
    when :blocked then redirect_to listing_path(listing), alert: t(".blocked")
    end
  end

  private

    def set_conversation
      @conversation = Conversation.for_user(current_user).find(params[:id])
    end
end
