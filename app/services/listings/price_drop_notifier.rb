module Listings
  # Alerts the users who saved a listing when its price is cut. Rate-limited
  # to one burst per listing per COOLDOWN window (checked against the
  # price_drop Notification rows already written), so sellers nudging the
  # price down several times a day only spam wishlists once.
  class PriceDropNotifier
    COOLDOWN = 24.hours

    def self.call(listing) = new(listing).call

    def initialize(listing)
      @listing = listing
    end

    def call
      return unless @listing.approved?
      return if recently_notified?

      saved_before_the_cut = @listing.favorites
                                     .where("price_cents_at_save IS NULL OR price_cents_at_save > ?",
                                            @listing.price_cents)
      return unless saved_before_the_cut.exists?

      payload = {
        "listing_id" => @listing.id,
        "title" => @listing.title,
        "price_cents" => @listing.price_cents,
        "currency" => @listing.currency
      }

      saved_before_the_cut.find_each do |favorite|
        Notification.create!(user: favorite.user, kind: "price_drop", payload: payload)
        # The in-app alert always lands; the e-mail honours the channel
        # preference (the mailer action double-checks it at delivery time).
        next unless favorite.user.wants_email?("price_drop")

        PriceDropMailer.with(user: favorite.user, listing: @listing).price_drop.deliver_later
      end
    end

    private

    def recently_notified?
      Notification.where(kind: "price_drop")
                  .where("payload->>'listing_id' = ?", @listing.id.to_s)
                  .where(created_at: COOLDOWN.ago..)
                  .exists?
    end
  end
end
