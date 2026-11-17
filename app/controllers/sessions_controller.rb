class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: t(".rate_limited") }

  def new
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      if user.banned?
        # The ban reason is internal text; surface it only after the fixed
        # sentence so the user knows why (and to contact support).
        alert = [ t(".banned"), user.ban_reason ].compact_blank.join(" — ")
        redirect_to new_session_path, alert: alert
      else
        start_new_session_for user
        redirect_to after_authentication_url
      end
    else
      redirect_to new_session_path, alert: t(".invalid_credentials")
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
