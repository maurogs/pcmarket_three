module Offers
  # Places a buyer's offer on a listing. Rules (all reported as Result#error,
  # never raised): the listing must be approved, accept offers and not be on
  # vacation; the buyer cannot offer on their own listing; the amount is
  # positive, strictly under the asking price and at least
  # Setting["min_offer_percent"] (default 50) of it. Any older pending offer
  # from the same buyer is withdrawn — one pending offer per buyer, always.
  # The accepted-offer reservation and 48h expiry live on Offer/Listing; the
  # offer also posts a chat card ("Offer of 450,00 € sent") into the thread.
  class Create
    DEFAULT_MIN_PERCENT = 50

    Result = Struct.new(:offer, :error, :min_amount_cents, keyword_init: true)

    def self.call(listing:, buyer:, amount_cents:)
      new(listing:, buyer:, amount_cents:).call
    end

    def initialize(listing:, buyer:, amount_cents:)
      @listing = listing
      @buyer = buyer
      @amount_cents = amount_cents
    end

    def call
      return error(:self) if listing.user_id == buyer.id
      return error(:not_allowed) unless listing.approved? && listing.offers_allowed?
      return error(:vacation) if listing.store&.vacation_mode?

      amount = amount_cents
      return error(:invalid) unless amount.is_a?(Integer) && amount.positive?

      min = minimum_amount_cents
      return Result.new(error: :below_minimum, min_amount_cents: min) if amount < min
      return error(:above_price) if amount >= listing.price_cents

      offer = transaction do
        # A new offer replaces the buyer's previous pending one.
        Offer.active.where(listing: listing, buyer: buyer).not_expired.find_each(&:withdraw!)

        created = Offer.create!(
          listing: listing, buyer: buyer, amount_cents: amount,
          expires_at: Time.current + Offer::OFFER_TTL
        )
        post_to_chat(created)
        created
      end

      Result.new(offer: offer)
    end

    # Minimum accepted amount in cents for a listing (ceil of the percent).
    def self.minimum_for(listing)
      percent = Integer(Setting.get("min_offer_percent", DEFAULT_MIN_PERCENT))
      (listing.price_cents * percent).fdiv(100).ceil
    end

    private

    attr_reader :listing, :buyer, :amount_cents

    def minimum_amount_cents
      self.class.minimum_for(listing)
    end

    def error(name)
      Result.new(error: name, min_amount_cents: name == :below_minimum ? minimum_amount_cents : nil)
    end

    def post_to_chat(offer)
      conversation = Conversation.find_or_create_by!(
        listing: listing, buyer: buyer, seller_id: listing.user_id
      )
      Message.create!(
        conversation: conversation, sender: buyer, kind: :offer, offer: offer,
        body: I18n.t("offers.chat.offer_sent", amount: offer.price.formatted)
      )
      Notification.create!(
        user_id: listing.user_id, kind: "new_offer",
        payload: { "offer_id" => offer.id }
      )
    end

    def transaction(&block)
      ActiveRecord::Base.transaction(&block)
    end
  end
end
