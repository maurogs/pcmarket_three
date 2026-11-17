module Carts
  # Read model for the cart page and the checkout: groups the cart by
  # seller (one order per seller at checkout), flags items whose listing
  # has stopped being purchasable since they were added (greyed out,
  # excluded from totals) and prices EVERYTHING from the live listing
  # rows — stored prices are never trusted.
  #
  # Shipping per seller: free when every item of the group offers free
  # shipping or the group subtotal reaches the store's
  # free_shipping_threshold_cents; otherwise the highest
  # shipping_price_cents among the group's items.
  class Summary
    Item = Struct.new(:cart_item, :listing, :stale, keyword_init: true) do
      def quantity = cart_item.quantity

      def listing_id = cart_item.listing_id

      def line_total_cents
        listing.price_cents * quantity
      end
    end

    Group = Struct.new(:seller, :store, :items, keyword_init: true) do
      def live_items = items.reject(&:stale)

      def any_live? = live_items.any?

      def subtotal_cents = live_items.sum(&:line_total_cents)

      def free_shipping?
        live_items.all? { |item| item.listing.free_shipping } ||
          (store&.free_shipping_threshold_cents.present? &&
            subtotal_cents >= store.free_shipping_threshold_cents)
      end

      def shipping_cents
        return 0 unless any_live?
        return 0 if free_shipping?

        live_items.map { |item| item.listing.shipping_price_cents }.max
      end

      # Local pickup is offered only when every live item of the seller
      # can be picked up.
      def pickup_available?
        any_live? && live_items.all? { |item| item.listing.local_pickup }
      end

      def total_cents = subtotal_cents + shipping_cents
    end

    attr_reader :cart, :groups

    def initialize(cart)
      @cart = cart
      @groups = build_groups
    end

    def items = groups.flat_map(&:items)

    def live_items = groups.flat_map(&:live_items)

    def stale_items = groups.flat_map { |g| g.items.select(&:stale) }

    def any_stale? = groups.any? { |g| g.items.any?(&:stale) }

    def empty? = items.empty?

    def total_quantity = items.sum(&:quantity)

    def subtotal_cents = groups.sum(&:subtotal_cents)

    # pickup_seller_ids: sellers the buyer chose local pickup for at
    # checkout (ignored — i.e. always charged — on the cart page).
    def shipping_cents(pickup_seller_ids: [])
      groups.sum do |group|
        if pickup_seller_ids.include?(group.seller.id) && group.pickup_available?
          0
        else
          group.shipping_cents
        end
      end
    end

    def total_cents(pickup_seller_ids: [])
      subtotal_cents + shipping_cents(pickup_seller_ids: pickup_seller_ids)
    end

    # Listings that can actually be ordered (drives the checkout gate).
    def orderable? = live_items.any?

    private

    def build_groups
      loaded = cart.cart_items.includes(listing: [ :store, :user ]).to_a
      buyer = cart.user

      by_seller = loaded.group_by { |item| item.listing.user_id }
      # Stable order: the first add-to-cart moment of each seller group.
      ordered_ids = by_seller.sort_by { |_seller_id, cart_items| cart_items.map(&:created_at).min }.map(&:first)

      ordered_ids.map do |seller_id|
        cart_items = by_seller[seller_id].sort_by(&:created_at)
        first = cart_items.first.listing
        Group.new(
          seller: first.user,
          store: first.store,
          items: cart_items.map do |cart_item|
            listing = cart_item.listing
            Item.new(cart_item: cart_item, listing: listing,
                     stale: !listing.purchasable_by?(buyer))
          end
        )
      end
    end
  end
end
