module Api
  module V1
    # The signed-in user's cart (guest carts are cookie-only and out of
    # scope for the API). Carts::Summary prices everything from the live
    # listing rows and flags stale items, so the totals here match the web
    # cart page exactly; checkout_available is the same orderable? gate the
    # web uses to enable its checkout button.
    class CartsController < BaseController
      before_action :verify_user!

      def show
        @cart = Cart.for_user(current_user)
        @summary = Carts::Summary.new(@cart)
      end

      def destroy
        Cart.for_user(current_user).cart_items.delete_all
        render json: { message: t("api.carts.emptied") }
      end
    end
  end
end
