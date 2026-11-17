module Checkout
  # Launch payment mode ("arrange payment with the seller"): after the
  # orders are placed, a system message with the order number is posted
  # into the buyer↔seller thread of each order. The service returns where
  # to send the buyer (one order → that thread; several sellers → the
  # conversation list). The seller confirms receipt from the sale page
  # (payment_confirmation resource).
  class DirectPayment
    Result = Struct.new(:conversation, :multiple, keyword_init: true)

    def self.call(orders:, buyer:)
      new(orders: orders, buyer: buyer).call
    end

    def initialize(orders:, buyer:)
      @orders = orders
      @buyer = buyer
    end

    def call
      conversations = orders.filter_map { |order| post_system_message(order) }
      Result.new(conversation: conversations.first, multiple: conversations.size > 1)
    end

    private

    attr_reader :orders, :buyer

    # The thread is seeded from the listing of the order's first item.
    def post_system_message(order)
      listing = order.order_items.where.not(listing_id: nil).first&.listing
      return nil if listing.nil?

      conversation = Conversation.find_or_create_by!(
        listing: listing, buyer: buyer, seller_id: order.seller_id
      )
      Message.create!(
        conversation: conversation, sender: buyer, kind: :system,
        body: I18n.t("checkouts.direct.system_message", number: order.number)
      )
      conversation
    end
  end
end
