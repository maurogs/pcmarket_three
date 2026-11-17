module Api
  module V1
    # Cart line items for the signed-in user. Every lookup goes through the
    # user's own cart (other people's items 404) and every purchase rule is
    # Carts::AddItem's — including quantity stacking and the stock cap.
    # PATCH/PUT with quantity 0 removes the line, the web cart's "−" behaviour.
    class CartItemsController < BaseController
      before_action :verify_user!
      before_action :set_cart_item, only: %i[update destroy]

      def index
        @cart_items = cart.cart_items.includes(listing: [ :store, :user ]).order(:created_at)
      end

      def create
        listing = Listing.friendly.find(params.require(:listing_id))
        result = Carts::AddItem.call(cart: cart, listing: listing, quantity: params[:quantity] || 1)

        if result.cart_item
          @cart_item = result.cart_item
          render :create, status: :created
        else
          render_add_error(result.error, listing)
        end
      end

      def update
        quantity = Integer(params.require(:quantity)) rescue nil

        if quantity.nil? || quantity.negative?
          return render_error(:unprocessable_entity, :invalid_quantity,
                              message: t("api.cart_items.update_errors.invalid"))
        end

        if quantity.zero?
          @cart_item.destroy
          return render json: { cart_item: nil, message: t("api.cart_items.destroyed") }
        end

        listing = @cart_item.listing
        if quantity > listing.quantity
          return render_error(:unprocessable_entity, :quantity_exceeded,
                              message: t("api.cart_items.update_errors.quantity_exceeded",
                                         count: listing.quantity))
        end
        unless listing.purchasable_by?(current_user)
          return render_error(:unprocessable_entity, :not_purchasable,
                              message: t("api.cart_items.update_errors.not_purchasable"))
        end

        @cart_item.update!(quantity: quantity)
        @message = t("api.cart_items.updated")
        render :update
      end

      def destroy
        @cart_item.destroy
        render json: { message: t("api.cart_items.destroyed") }
      end

      private

        def cart
          @cart ||= Cart.for_user(current_user)
        end

        def set_cart_item
          @cart_item = cart.cart_items.find(params[:id])
        end

        # AddItem error names mapped onto the shared envelope. not_found
        # cannot happen here (friendly.find raises first).
        def render_add_error(error, listing)
          case error
          when :own_listing then render_error(:unprocessable_entity, :own_listing, message: t("api.checkouts.errors.own_listing"))
          when :vacation then render_error(:unprocessable_entity, :vacation, message: t("api.checkouts.errors.vacation"))
          when :not_purchasable then render_error(:unprocessable_entity, :not_purchasable, message: t("api.cart_items.update_errors.not_purchasable"))
          when :quantity_exceeded then render_error(:unprocessable_entity, :quantity_exceeded,
                                                    message: t("api.cart_items.update_errors.quantity_exceeded", count: listing.quantity))
          else render_error(:unprocessable_entity, :invalid_quantity, message: t("api.cart_items.update_errors.invalid"))
          end
        end
    end
  end
end
