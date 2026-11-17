module Api
  module V1
    # Token self-service: list the ACTIVE tokens (metadata only — the
    # plaintext is shown exactly once at issue time) and revoke any of
    # them. Revoking the token used for the current request takes effect
    # immediately: the digest is gone, so the next call 401s.
    class ApiTokensController < BaseController
      before_action :verify_user!

      def index
        @api_tokens = current_user.api_tokens.active.order(created_at: :desc)
      end

      def destroy
        current_user.api_tokens.find(params[:id]).destroy!
        render json: { message: t("api.api_tokens.destroyed") }
      end
    end
  end
end
