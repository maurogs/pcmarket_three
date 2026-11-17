module Account
  # Public profile fields: name, email, phone, language. Changing the
  # language re-signs the whole path prefix into the new locale.
  class ProfilesController < BaseController
    def show
    end

    def update
      if current_user.update(profile_params)
        redirect_to account_profile_path(locale: current_user.locale), notice: t(".updated")
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def profile_params
      params.require(:user).permit(:first_name, :last_name, :email_address, :phone, :locale)
    end
  end
end
