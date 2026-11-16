module Sell
  # Store settings form (singular resource: one store per user). Updates run
  # through Stores::UpdateSettings; a renamed store keeps serving its old
  # public URL via FriendlyId history (301 in StoresController#show).
  class StoresController < BaseController
    def edit
      @store = current_user.store ||
               Store.new(user: current_user, name: current_user.username, store_type: :individual)
    end

    def update
      result = Stores::UpdateSettings.new(current_user, store_params).call
      @store = result.store

      if result.saved?
        redirect_to edit_sell_store_path, notice: t(".updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def store_params
      params.require(:store).permit(
        :name, :description, :store_type, :vat_number, :allow_offers_default,
        :city, :region, :default_shipping, :free_shipping_threshold,
        :returns_policy, :shipping_policy, :logo, :banner
      ).to_h
    end
  end
end
