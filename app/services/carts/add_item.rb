module Carts
  # The only way a listing enters a cart. Rules (reported as Result#error,
  # never raised): the listing must be approved — or reserved FOR this
  # buyer — the buyer cannot buy their own listing, the seller must not be
  # on vacation, and the cart quantity for that listing may not exceed the
  # listing's stock. Re-adding an existing item stacks onto its quantity.
  class AddItem
    Result = Struct.new(:cart_item, :error, keyword_init: true) do
      def success? = error.nil?
    end

    def self.call(cart:, listing:, quantity: 1)
      new(cart: cart, listing: listing, quantity: quantity).call
    end

    def initialize(cart:, listing:, quantity:)
      @cart = cart
      @listing = listing
      @quantity = quantity
    end

    def call
      return error(:not_found) if listing.nil?
      return error(:own_listing) if cart.user_id.present? && listing.user_id == cart.user_id
      return error(:vacation) if listing.store&.vacation_mode?
      return error(:not_purchasable) unless listing.purchasable_by?(cart.user)

      units = Integer(quantity) rescue nil
      return error(:invalid_quantity) if units.nil? || units <= 0

      item = cart.cart_items.find_or_initialize_by(listing_id: listing.id)
      total = (item.persisted? ? item.quantity : 0) + units
      return error(:quantity_exceeded) if total > listing.quantity

      item.quantity = total
      return error(:invalid) unless item.save

      Result.new(cart_item: item)
    end

    private

    attr_reader :cart, :listing, :quantity

    def error(name)
      Result.new(error: name)
    end
  end
end
