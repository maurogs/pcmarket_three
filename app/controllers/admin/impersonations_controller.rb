module Admin
  # "Log in as" support tooling. create switches the browser to a fresh
  # session for a NON-admin target, remembering the impersonator in the
  # cookie session; the sticky red banner's stop button posts DELETE here.
  # destroy therefore skips the admin guard (Current.user is the target
  # then) and authenticates itself via the stored impersonator id.
  class ImpersonationsController < BaseController
    include Auditable

    skip_before_action :require_admin!, only: :destroy

    def create
      @user = User.find(params[:user_id])

      if @user.admin? || @user.id == Current.user.id || @user.deleted?
        redirect_to admin_user_path(@user), alert: t("admin.impersonation.create.not_allowed") and return
      end

      audit!(:impersonation_start, @user)
      session[:impersonator_id] = Current.user.id
      session[:impersonated_user_id] = @user.id
      start_new_session_for(@user)
      redirect_to root_path, notice: t("admin.impersonation.create.started", name: @user.display_name)
    end

    def destroy
      target = Current.user
      impersonator = User.find_by(id: session[:impersonator_id])

      # Only ever reachable from a live impersonation started by a real admin.
      if target.nil? || impersonator.nil? || impersonator.id == target.id || !impersonator.admin?
        raise ActiveRecord::RecordNotFound
      end

      Current.session.destroy
      cookies.delete(:session_id)
      session.delete(:impersonator_id)
      session.delete(:impersonated_user_id)
      start_new_session_for(impersonator)

      audit!(:impersonation_stop, target)
      redirect_to admin_user_path(target), notice: t("admin.impersonation.destroy.stopped", name: target.display_name)
    end
  end
end
