module Offers
  # Seller's no. Only a pending offer can be declined; anything else is
  # reported as :stale (the controllers turn that into a flash).
  class Decline
    Result = Struct.new(:offer, :error, keyword_init: true)

    def self.call(offer:)
      new(offer:).call
    end

    def initialize(offer:)
      @offer = offer
    end

    def call
      offer.decline!
      Result.new(offer: offer)
    rescue Offer::InvalidTransition
      Result.new(error: :stale)
    end

    private

    attr_reader :offer
  end
end
