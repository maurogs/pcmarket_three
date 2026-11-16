module Offers
  # Seller's yes. Accepting an offer reserves the listing for that buyer for
  # Listing::RESERVATION_TTL, auto-declines every other pending offer on the
  # same listing and notifies the buyer. Guard failures (offer no longer
  # pending, listing no longer approved) come back as :stale.
  class Accept
    Result = Struct.new(:offer, :error, keyword_init: true)

    def self.call(offer:)
      new(offer:).call
    end

    def initialize(offer:)
      @offer = offer
    end

    def call
      ActiveRecord::Base.transaction do
        offer.accept!
        offer.listing.reserve_for!(offer.buyer)
        Offer.active.where(listing_id: offer.listing_id).where.not(id: offer.id)
             .find_each(&:decline!)
        Notification.create!(
          user: offer.buyer, kind: "offer_accepted",
          payload: { "offer_id" => offer.id }
        )
      end
      Result.new(offer: offer)
    rescue Offer::InvalidTransition, Listing::InvalidTransition
      Result.new(error: :stale)
    end

    private

    attr_reader :offer
  end
end
