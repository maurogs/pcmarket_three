module Sell
  # Vacation-mode toggle (Phase 3b). POST creates the vacation state, DELETE
  # leaves it. Listings stay public; the storefront and listing pages show a
  # notice and disable the buy/offer CTAs.
  class VacationsController < BaseController
    def create
      store = Stores::EnsureFor.new(current_user).call
      store.enable_vacation!
      redirect_to sell_dashboard_path, notice: t(".enabled")
    end

    def destroy
      current_user.store&.disable_vacation!
      redirect_to sell_dashboard_path, notice: t(".disabled")
    end
  end
end
