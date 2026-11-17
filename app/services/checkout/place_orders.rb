module Checkout
  # Places the cart: one Order per seller group (see Carts::Summary), all
  # inside one transaction with every listing row locked (SELECT ... FOR
  # UPDATE, ids locked in ascending order to avoid deadlocks) and
  # re-validated — a listing sold underneath the buyer makes the whole
  # checkout fail without creating any order.
  #
  # Totals, shipping and commission are recomputed from the locked
  # listing rows; the form only chooses the shipping address and per-seller
  # ship/pickup options. Orders start as pending_payment with
  # buyer_protection_until nil (the protection window starts at delivery).
  #
  # Idempotency: the checkout form carries a one-time checkout_token (kept
  # in the session); replaying the same token returns the orders already
  # created for it instead of placing new ones.
  class PlaceOrders
    Result = Struct.new(:orders, :error, keyword_init: true) do
      def success? = error.nil?
    end

    def self.call(buyer:, cart:, address:, checkout_token:, pickup_seller_ids: [], payment_provider: nil)
      new(buyer: buyer, cart: cart, address: address, checkout_token: checkout_token,
          pickup_seller_ids: pickup_seller_ids, payment_provider: payment_provider).call
    end

    def initialize(buyer:, cart:, address:, checkout_token:, pickup_seller_ids:, payment_provider:)
      @buyer = buyer
      @cart = cart
      @address = address
      @checkout_token = checkout_token
      @pickup_seller_ids = Array(pickup_seller_ids).map(&:to_i)
      @payment_provider = payment_provider
    end

    def call
      return Result.new(error: :invalid_token) if checkout_token.blank?
      return Result.new(error: :invalid_address) if address.nil?

      existing = Order.where(checkout_token: checkout_token)
      return Result.new(orders: existing.recent.to_a) if existing.exists?

      @summary = Carts::Summary.new(cart)
      return Result.new(error: :empty_cart) unless @summary.orderable?

      @failure = nil
      orders = nil

      ActiveRecord::Base.transaction do
        listings = lock_and_validate
        if @failure
          raise ActiveRecord::Rollback
        end

        orders = create_orders(listings)
        clear_purchased_items(listings)
        notify_parties(orders)
      end

      return Result.new(error: @failure) if @failure

      Result.new(orders: orders)
    end

    private

    attr_reader :buyer, :cart, :address, :checkout_token, :pickup_seller_ids,
                :payment_provider, :summary

    # Lock each listing and re-check every purchase rule against the
    # locked row. Returns the locked listings, or sets @failure.
    def lock_and_validate
      ids = summary.live_items.map(&:listing_id).uniq.sort
      by_id = ids.map { |id| Listing.find(id).lock! }.index_by(&:id)

      summary.live_items.each do |item|
        listing = by_id.fetch(item.listing_id)

        if listing.user_id == buyer.id
          @failure = :own_listing
          return nil
        elsif listing.store&.vacation_mode?
          @failure = :vacation
          return nil
        elsif !listing.purchasable_by?(buyer)
          @failure = :not_purchasable
          return nil
        elsif item.quantity > listing.quantity
          @failure = :quantity_exceeded
          return nil
        end
      end

      by_id.values
    end

    # One order per seller group, in the cart's group order. Shipping
    # follows the cart rules (see Carts::Summary); pickup is only honoured
    # where every item of the group allows it. Commission is charged via
    # CommissionCalculator (0 unless the :commissions flag is on).
    def create_orders(locked_listings)
      units_by_listing_id = locked_listings.to_h do |listing|
        [ listing.id, summary.live_items.select { |i| i.listing_id == listing.id }.sum(&:quantity) ]
      end
      by_id = locked_listings.index_by(&:id)

      summary.groups.filter_map do |group|
        listings = group.items.reject(&:stale).map { |item| by_id.fetch(item.listing_id) }
        next if listings.empty?

        subtotal = listings.sum { |listing| listing.price_cents * units_by_listing_id.fetch(listing.id) }
        pickup = pickup_seller_ids.include?(group.seller.id) && listings.all?(&:local_pickup)
        commission = CommissionCalculator.new(total_cents: subtotal).call

        order = Order.create!(
          buyer: buyer, seller: group.seller, checkout_token: checkout_token,
          shipping_address: address.to_snapshot,
          subtotal_cents: subtotal,
          shipping_cents: shipping_cents(listings, subtotal, pickup),
          commission_cents: commission, currency: listings.first.currency,
          payment_provider: payment_provider
        )

        listings.each do |listing|
          units = units_by_listing_id.fetch(listing.id)
          order.order_items.create!(listing: listing, title: listing.title,
                                    price_cents: listing.price_cents, quantity: units)
          consume_listing(listing, units)
        end

        order
      end
    end

    def shipping_cents(listings, subtotal, pickup)
      return 0 if pickup
      return 0 if listings.all?(&:free_shipping)

      store = listings.first.store
      if store&.free_shipping_threshold_cents.present? && subtotal >= store.free_shipping_threshold_cents
        return 0
      end

      listings.map(&:shipping_price_cents).max
    end

    # Decrement stock; when the last unit goes the listing is marked sold.
    # (quantity 0 would violate the >0 validation, so after the status
    # change the column is zeroed through the connection — sold listings
    # are out of the sale pool anyway.)
    def consume_listing(listing, units)
      if listing.quantity <= units
        listing.mark_sold!
        listing.update_column(:quantity, 0)
      else
        listing.update!(quantity: listing.quantity - units)
      end
    end

    def clear_purchased_items(locked_listings)
      cart.cart_items.where(listing_id: locked_listings.map(&:id)).delete_all
    end

    # Notification rows + e-mails: the seller gets "new sale", the buyer
    # the order confirmation.
    def notify_parties(orders)
      orders.each do |order|
        Notification.create!(user: order.seller, kind: "order_placed",
                             payload: { "order_id" => order.id })
        Notification.create!(user: order.buyer, kind: "order_confirmed",
                             payload: { "order_id" => order.id })
        OrderMailer.with(order: order, recipient: order.seller).new_sale.deliver_later
        OrderMailer.with(order: order, recipient: order.buyer).confirmation.deliver_later
      end
    end
  end
end
