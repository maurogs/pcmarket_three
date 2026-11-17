module Api
  module V1
    # POST /api/v1/session — email + password in, bearer token out. Mirrors
    # SessionsController: same User.authenticate_by lookup, same ban refusal.
    # Each sign-in issues a fresh ApiToken (the plaintext is shown once).
    # DELETE /api/v1/session revokes the token in use.
    class SessionsController < BaseController
      skip_before_action :authenticate_token!, only: :create

      # Same throttle the web sign-in form uses (10 / 3 minutes).
      rate_limit to: 10, within: 3.minutes, only: :create,
                 by: -> { request.remote_ip },
                 with: -> { render_error(:too_many_requests, :rate_limited) }

      def create
        user = User.authenticate_by(email_address: params[:email_address].to_s,
                                    password: params[:password].to_s)
        return render_error(:unauthorized, :unauthorized) if user.nil?

        if user.banned?
          return render_error(:forbidden, :banned, message: t("api.sessions.banned"))
        end

        @token = ApiToken.issue_for(user, name: "API #{request.user_agent.to_s.slice(0, 60)}")
        @user = user
      end

      def destroy
        Current.api_token.destroy!
        render json: { message: t("api.sessions.destroyed") }
      end
    end
  end
end
