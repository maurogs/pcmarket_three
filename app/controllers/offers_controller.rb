# Buyer-side offers: the modal form (nested under a listing) and the
# received/sent inbox tab. All reads are scoped — a buyer's "sent" list is
# current_user.offers, the seller's "received" list joins their own
# listings — and a foreign or self listing 404s before any rules run.
class OffersController < ApplicationController
  TABS = %w[received sent].freeze

  def index
    @tab = TABS.include?(params[:tab]) ? params[:tab] : "received"
    relation = @tab == "received" ? Offer.for_seller(current_user) : Offer.sent_by(current_user)

    @received_count = Offer.for_seller(current_user).count
    @sent_count = Offer.sent_by(current_user).count
    @pagy, @offers = pagy(
      relation.includes(listing: { photos_attachments: :blob }, buyer: :store),
      limit: 20
    )
  end

  def new
    @listing = find_offerable_listing
    @offer = Offer.new(listing: @listing)
  end

  def create
    @listing = find_offerable_listing
    @amount = params.dig(:offer, :amount)

    cents = Listings::FormAttributes.euros_to_cents(@amount)
    cents = nil if cents == Listings::FormAttributes::INVALID

    result = Offers::Create.call(listing: @listing, buyer: current_user, amount_cents: cents)

    if result.offer
      redirect_to conversation_path(result.offer.conversation), notice: t(".created")
    else
      @error = create_error_message(result)
      render :new, status: :unprocessable_entity
    end
  end

  private

  # Only public, approved listings accept offers; the owner is not even
  # shown the resource (404, same discipline as every other lookup). Reserved
  # listings pass the lookup so the form can explain *why* it refuses (422).
  def find_offerable_listing
    listing = Listing.friendly.find(params[:listing_id])
    raise ActiveRecord::RecordNotFound unless listing.approved? || listing.reserved?
    raise ActiveRecord::RecordNotFound if listing.user_id == current_user.id

    listing
  end

  def create_error_message(result)
    key = "offers.create.errors.#{result.error}"
    if result.error == :below_minimum
      t(key, min: Money.new(result.min_amount_cents, @listing.currency).formatted)
    else
      t(key)
    end
  end
end
