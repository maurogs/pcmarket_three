module Admin
  # Ban flow: new renders the reason form, create runs Users::Ban (sessions
  # + tokens destroyed, live listings archived), destroy is the unban.
  class BansController < BaseController
    include Auditable

    before_action :set_user

    def new
    end

    def create
      if @user.id == Current.user.id
        redirect_to admin_users_path, alert: t(".cannot_ban_self") and return
      end

      Users::Ban.call(@user, reason: params[:ban_reason])
      audit!(:ban_user, @user, reason: params[:ban_reason].presence)
      redirect_to admin_user_path(@user), notice: t(".banned", name: @user.display_name)
    end

    def destroy
      Users::Unban.call(@user)
      audit!(:unban_user, @user)
      redirect_to admin_user_path(@user), notice: t(".unbanned", name: @user.display_name)
    end

    private

    def set_user
      @user = User.find(params[:user_id])
    end
  end
end
