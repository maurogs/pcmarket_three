# Chat inbox over the web Conversation model (Phase 4a rules: every lookup
# goes through Conversation.for_user, so outsiders 404). Creating starts a
# thread via Conversations::Start and optionally posts the first message
# through Messages::Send in one round trip — the body is never written
# directly to the DB here.
class Api::V1::ConversationsController < Api::V1::BaseController
  before_action :verify_user!
  before_action :set_conversation, only: :show

  def index
    @pagy, @conversations = pagy(
      Conversation.for_user(current_user).recent
                  .includes(:buyer, :seller, listing: { photos_attachments: :blob }),
      limit: page_size
    )
    @unread_counts = Conversation.unread_counts_by_conversation_for(current_user, @conversations)
    @last_messages = last_messages_by_conversation
    set_link_header @pagy
  end

  # Opening a thread marks the other party's messages read (same side effect
  # as the web show) so unread badges stay truthful across clients.
  def show
    @conversation.mark_messages_read_for(current_user)
    Conversation.clear_unread_cache(current_user)
    @messages = @conversation.messages.order(:created_at, :id).includes(:sender, offer: :listing)
  end

  # POST /api/v1/conversations { listing_id, body? }. The listing visibility
  # rule matches the web "Message seller": approved/reserved, or the owner,
  # or an admin — everything else 404s.
  def create
    listing = Listing.friendly.find(params.require(:listing_id))
    unless listing.approved? || listing.reserved? || listing.user_id == current_user.id || current_user.admin?
      raise ActiveRecord::RecordNotFound
    end

    result = Conversations::Start.call(user: current_user, listing: listing)
    case result.error
    when :self then render_error(:unprocessable_entity, "self", message: t("api.conversations.errors.self"))
    when :blocked then render_error(:unprocessable_entity, "blocked", message: t("api.conversations.errors.blocked"))
    else
      @message = nil
      body = params[:body].presence
      if body
        sent = Messages::Send.call(conversation: result.conversation, sender: current_user, body: body)
        @message = sent.message
      end

      @conversation = result.conversation.reload
      render :create, status: :created
    end
  end

  private

  def set_conversation
    @conversation = Conversation.for_user(current_user).find(params[:id])
  end

  # One grouped query for the page's previews (same as the web inbox).
  def last_messages_by_conversation
    ids = @conversations.map(&:id)
    return {} if ids.empty?

    Message.where(conversation_id: ids)
           .where("messages.id IN (SELECT MAX(id) FROM messages WHERE conversation_id IN (?) GROUP BY conversation_id)", ids)
           .index_by(&:conversation_id)
  end
end
