module Api
  module V1
    # Messages inside one thread (nested under a conversation). Reads and
    # writes go through the conversation, and every conversation lookup runs
    # through Conversation.for_user, so outsiders 404 (Phase 4a discipline).
    # Sending is exclusively Messages::Send — the block checks, length caps
    # and notification fan-out are the web's rules, not reimplemented here.
    class MessagesController < BaseController
      before_action :verify_user!
      before_action :set_conversation

      DEFAULT_LIMIT = 50
      MAX_LIMIT = 100

      # Cursor pagination instead of pages: chat clients page backwards
      # with ?before_id=<oldest id seen>. The page comes back chronological,
      # with has_more telling the client whether older messages exist.
      def index
        limit = params[:limit].to_i
        limit = DEFAULT_LIMIT unless limit.between?(1, MAX_LIMIT)
        before_id = params[:before_id].to_i
        before_id = nil if before_id <= 0

        scope = @conversation.messages.includes(:sender).order(created_at: :desc, id: :desc)
        scope = scope.where("messages.id < ?", before_id) if before_id

        rows = scope.limit(limit + 1).to_a
        @has_more = rows.size > limit
        @messages = rows.first(limit).reverse
        @before_id = before_id
      end

      def create
        result = Messages::Send.call(conversation: @conversation, sender: current_user,
                                     body: params[:body])

        case result.error
        when :blocked then render_error(:unprocessable_entity, :blocked, message: t("api.messages.errors.blocked"))
        when :not_participant then render_error(:not_found, :not_found)
        when nil
          @message = result.message
          render :create, status: :created
        else
          render_error(:unprocessable_entity, :invalid_request,
                       details: { body: message_error_text(result.error) })
        end
      end

      private

        def set_conversation
          @conversation = Conversation.for_user(current_user).find(params[:conversation_id])
        end

        # Map the Send result codes onto localized field messages; Message's
        # own validations cover the rest.
        def message_error_text(error)
          case error
          when :blank then Message.human_attribute_name(:body) + " " + I18n.t("errors.messages.blank")
          when :too_long
            Message.human_attribute_name(:body) + " " +
              I18n.t("errors.messages.too_long", count: Message::MAX_BODY_LENGTH)
          else t("api.errors.invalid_request")
          end
        end
    end
  end
end
