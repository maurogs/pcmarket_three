module Admin
  # Verified badge toggle: POST creates the badge, DELETE removes it.
  class VerificationsController < BaseController
    include Auditable

    before_action :set_store

    def create
      @store.update!(verified: true)
      audit!(:verify_store, @store)
      redirect_to admin_store_path(@store), notice: t(".verified")
    end

    def destroy
      @store.update!(verified: false)
      audit!(:unverify_store, @store)
      redirect_to admin_store_path(@store), notice: t(".unverified")
    end

    private

    def set_store
      @store = Store.friendly.find(params[:store_id])
    end
  end
end
