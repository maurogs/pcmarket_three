module Admin
  # Hide toggle (Store#hidden: out of public catalogues and store pages):
  # POST hides, DELETE reveals again.
  class HidingsController < BaseController
    include Auditable

    before_action :set_store

    def create
      @store.update!(hidden: true)
      audit!(:hide_store, @store)
      redirect_to admin_store_path(@store), notice: t(".hidden")
    end

    def destroy
      @store.update!(hidden: false)
      audit!(:unhide_store, @store)
      redirect_to admin_store_path(@store), notice: t(".unhidden")
    end

    private

    def set_store
      @store = Store.friendly.find(params[:store_id])
    end
  end
end
