module Admin
  # User management: filtered index, a 360° profile page (store, listing
  # counts by status, orders both sides, recent sessions, audit trail) and
  # guarded profile/role edits through Users::AdminUpdate.
  class UsersController < BaseController
    include Auditable

    PER_PAGE = 25

    before_action :set_user, only: %i[show edit update]

    def index
      @scope = Admin::UserFilter.call(params)
      @pagy, @users = pagy(@scope, limit: PER_PAGE)
    end

    def show
      @store = @user.store
      @listing_counts = Listing.status_counts(@user.listings)
      @archived_listings = @user.listings.where(status: :archived).order(updated_at: :desc).limit(10)
      @buyer_orders = @user.orders.recent.limit(5)
      @seller_orders = @user.sales.recent.limit(5)
      @recent_sessions = @user.sessions.order(created_at: :desc).limit(10)
      @audit_logs = AdminAuditLog.for_subject(@user).includes(:admin).recent.limit(20)
    end

    def edit
    end

    def update
      result = Users::AdminUpdate.call(@user, form_params, acting_admin: Current.user)
      @user = result.user

      if result.saved?
        audit!(:edit_user, @user, changes: @user.previous_changes.except("updated_at"))
        redirect_to admin_user_path(@user), notice: t(".updated", name: @user.display_name)
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    def form_params
      params.require(:user).permit(:first_name, :last_name, :email_address, :username,
                                   :country_code, :locale, :role)
    end
  end
end
