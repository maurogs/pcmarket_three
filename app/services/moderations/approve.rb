module Moderations
  # Approving a pending listing: model transition + seller notification
  # (in-app row + e-mail). Saved-search matching is already hooked into the
  # Listing after_commit on the ->approved transition, so it needs nothing
  # here. Raises Listing::InvalidTransition when the listing was already
  # reviewed.
  class Approve
    def self.call(listing, admin:)
      new(listing, admin).call
    end

    def initialize(listing, admin)
      @listing = listing
      @admin = admin
    end

    def call
      listing.approve!(admin)
      notify_seller
      listing
    end

    private

    attr_reader :listing, :admin

    def notify_seller
      Notification.create!(
        user: listing.user, kind: "listing_approved",
        payload: { "listing_id" => listing.id, "title" => listing.title }
      )
      ModerationMailer.approved(listing: listing, recipient: listing.user).deliver_later
    end
  end
end
