module Offers
  # Buyer takes their offer off the table. Only pending offers can be
  # withdrawn; anything else is :stale. (Offers::Create calls this itself
  # when a buyer replaces an older pending offer.)
  class Withdraw
    Result = Struct.new(:offer, :error, keyword_init: true)

    def self.call(offer:)
      new(offer:).call
    end

    def initialize(offer:)
      @offer = offer
    end

    def call
      offer.withdraw!
      Result.new(offer: offer)
    rescue Offer::InvalidTransition
      Result.new(error: :stale)
    end

    private

    attr_reader :offer
  end
end
