module Account
  # Password change: the current password must be confirmed.
  class SecuritiesController < BaseController
    def show
    end

    def update
      current_user.current_password = params[:user][:current_password].to_s
      unless current_user.authenticate(current_user.current_password)
        current_user.errors.add(:current_password, :invalid)
        render :show, status: :unprocessable_entity and return
      end

      if current_user.update(password: params[:user][:password],
                             password_confirmation: params[:user][:password_confirmation])
        redirect_to account_security_path, notice: t(".updated")
      else
        render :show, status: :unprocessable_entity
      end
    end
  end
end
