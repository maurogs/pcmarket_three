# Checkout (auth required — guests hitting it are sent to sign in with a
# return_to, via the standard require_authentication flow). One page with
# three steps: shipping address (a saved Address or a link to add one),
# shipping option per seller (ship / local pickup where allowed) and
# payment. Ordering itself lives in Checkout::PlaceOrders.
#
# Replay guard: every checkout render mints a fresh one-time token into
# the session and the form carries it. A submission whose token matches
# but already placed orders is a REPLAY (double click / browser resend):
# the buyer gets the existing orders instead of a second purchase. Stale
# forms (token from an older render) are refused.
class CheckoutsController < ApplicationController
  before_action :ensure_cart, only: :show

  def show
    @addresses = current_user.addresses.order(default_desc)
    @summary = Carts::Summary.new(current_cart)
    @checkout_token = fresh_checkout_token
    @stripe_mode = stripe_mode?
  end

  def create
    # The replay check runs BEFORE the empty-cart guard: the first submit
    # empties the cart, so a double click must still land on the replay
    # branch (redirect to the orders) instead of being bounced to the cart.
    token = params[:checkout_token].to_s
    return redirect_to(checkout_path, alert: t(".errors.invalid_token")) unless token == session[:checkout_token]

    existing = Order.where(checkout_token: token)
    if existing.exists?
      return redirect_to orders_path, notice: t(".replayed", count: existing.count)
    end

    address = current_user.addresses.find_by(id: params[:address_id])
    if address.nil?
      return redirect_to(checkout_path, alert: t(".errors.no_address"))
    end

    provider = stripe_mode? ? "stripe" : "direct"
    pickup_seller_ids = params.fetch(:pickup, {}).keys.filter_map { |k| k if k.match?(/\A\d+\z/) }

    result = Checkout::PlaceOrders.call(
      buyer: current_user, cart: current_cart, address: address,
      checkout_token: token, pickup_seller_ids: pickup_seller_ids,
      payment_provider: provider
    )

    if result.error
      return redirect_to(checkout_path, alert: t(".errors.#{result.error}"))
    end

    if stripe_mode?
      redirect_to_stripe(result.orders)
    else
      redirect_to_direct_payment(result.orders)
    end
  end

  private

  def default_desc
    Arel.sql('"addresses"."default" DESC, "addresses"."id"')
  end

  def ensure_cart
    return if current_cart.cart_items.exists?

    redirect_to cart_path, alert: t(".empty_cart")
  end

  def fresh_checkout_token
    session[:checkout_token] = SecureRandom.base58(24)
  end

  def stripe_mode?
    Flipper.enabled?(:stripe_checkout) && ENV["STRIPE_SECRET_KEY"].present?
  end

  def redirect_to_stripe(orders)
    result = Payments::StripeCheckout.call(
      orders: orders, buyer: current_user,
      success_url: orders_url(locale: I18n.locale, checkout: "success"),
      cancel_url: checkout_url(locale: I18n.locale, checkout: "cancelled")
    )
    redirect_to result.session.url, allow_other_host: true
  end

  def redirect_to_direct_payment(orders)
    result = Checkout::DirectPayment.call(orders: orders, buyer: current_user)

    if result.multiple
      redirect_to conversations_path, notice: t(".direct.multiple")
    else
      redirect_to conversation_path(result.conversation),
                  notice: t(".direct.placed", number: orders.map(&:number).join(", "))
    end
  end
end
