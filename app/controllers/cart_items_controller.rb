# Cart line edits (guests included — carts are resolved by
# ApplicationController#current_cart). All purchase rules live in
# Carts::AddItem; every lookup goes through the current cart, so other
# people's cart items 404. "Save to wishlist" is a PATCH intent: it needs
# an account, so guests are sent to sign in (and back to the cart).
class CartItemsController < ApplicationController
  allow_unauthenticated_access

  before_action :set_cart_item, only: %i[update destroy]

  def create
    listing = Listing.friendly.find(params[:listing_id])
    result = Carts::AddItem.call(cart: current_cart, listing: listing,
                                 quantity: params[:quantity])

    if result.cart_item
      redirect_to cart_path, notice: t(".added", title: listing.title)
    else
      redirect_to cart_path, alert: add_error_message(result.error)
    end
  end

  def update
    if params[:intent] == "wishlist"
      move_to_wishlist
    else
      update_quantity
    end
  end

  def destroy
    @cart_item.destroy
    redirect_to cart_path, notice: t(".removed")
  end

  private

  def set_cart_item
    @cart_item = current_cart.cart_items.find(params[:id])
  end

  def move_to_wishlist
    unless authenticated?
      session[:return_to_after_authenticating] = cart_path
      redirect_to new_session_path, alert: t("carts.show.wishlist_login_required") and return
    end

    Favorite.find_or_create_by!(user: current_user, listing: @cart_item.listing)
    @cart_item.destroy
    redirect_to cart_path, notice: t(".wishlist_saved", title: @cart_item.listing.title)
  end

  def update_quantity
    listing = @cart_item.listing
    quantity = Integer(params.dig(:cart_item, :quantity)) rescue nil

    if quantity.nil? || quantity <= 0
      redirect_to cart_path, alert: t(".errors.invalid_quantity")
    elsif quantity > listing.quantity
      redirect_to cart_path, alert: t(".errors.quantity_exceeded")
    else
      @cart_item.update!(quantity: quantity)
      redirect_to cart_path, notice: t(".updated")
    end
  end

  def add_error_message(error)
    t("carts.add_errors.#{error}")
  end
end
