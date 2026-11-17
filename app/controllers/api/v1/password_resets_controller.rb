module Api
  module V1
    # POST /api/v1/password_reset — same semantics as PasswordsController#create:
    # the e-mail is sent when the address exists, and the response is always
    # the same generic message (no account enumeration). The reset link itself
    # points at the web form.
    class PasswordResetsController < BaseController
      skip_before_action :authenticate_token!

      rate_limit to: 10, within: 3.minutes, only: :create,
                 by: -> { request.remote_ip },
                 with: -> { render_error(:too_many_requests, :rate_limited) }

      def create
        if (user = User.find_by(email_address: params[:email_address]))
          PasswordsMailer.reset(user).deliver_later
        end

        render json: { message: t("api.passwords.sent") }
      end
    end
  end
end
