module Api
  module V1
    # POST /api/v1/registration — same rules as RegistrationsController
    # (User validations do the work); on success the account is immediately
    # usable: a bearer token is issued like POST /session does.
    class RegistrationsController < BaseController
      skip_before_action :authenticate_token!

      rate_limit to: 10, within: 3.minutes, only: :create,
                 by: -> { request.remote_ip },
                 with: -> { render_error(:too_many_requests, :rate_limited) }

      def create
        @user = User.new(user_params)
        @user.locale = I18n.locale.to_s

        unless @user.save
          return render_error(:unprocessable_entity, :invalid_request,
                              details: @user.errors.as_json(full_messages: true))
        end

        @token = ApiToken.issue_for(@user, name: "API app")
      end

      private

      def user_params
        params.permit(:username, :email_address, :password, :password_confirmation,
                      :first_name, :last_name, :phone)
      end
    end
  end
end
