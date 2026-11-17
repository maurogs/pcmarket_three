module Admin
  # Store management: index (name search + verified/hidden filters), show
  # (owner, counters, live listings) and a details edit. Verified badges and
  # hiding are the nested verification/hiding resources.
  class StoresController < BaseController
    include Auditable

    PER_PAGE = 25

    before_action :set_store, only: %i[show edit update]

    def index
      scope = Store.includes(:user)
      if params[:q].present?
        like = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
        scope = scope.where("name ILIKE :q OR slug ILIKE :q", q: like)
      end
      scope = scope.where(verified: params[:verified] == "yes") if params[:verified].present?
      scope = scope.where(hidden: params[:hidden] == "yes") if params[:hidden].present?

      @pagy, @stores = pagy(scope.order(:name), limit: PER_PAGE)
    end

    def show
      @listings = @store.listings.order(created_at: :desc).limit(10)
    end

    def edit
    end

    def update
      if @store.update(store_params)
        audit!(:edit_store, @store, changes: @store.previous_changes.except("updated_at", "slug"))
        redirect_to admin_store_path(@store), notice: t(".updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_store
      @store = Store.friendly.find(params[:id])
    end

    def store_params
      params.require(:store).permit(:name, :description, :city, :region,
                                    :returns_policy, :shipping_policy)
    end
  end
end
