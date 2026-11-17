module Api
  module V1
    # Offer inbox (GET /api/v1/offers?role=received|sent) and creation
    # (POST /api/v1/listings/:listing_id/offers). The listing lookup mirrors
    # the web OffersController exactly — approved or reserved listings, never
    # the owner's own — and Offers::Create owns every rule (minimum amount,
    # one-pending-offer-per-buyer, chat card, notification).
    class OffersController < BaseController
      before_action :verify_user!

      def index
        relation = params[:role] == "sent" ? Offer.sent_by(current_user) : Offer.for_seller(current_user)
        @pagy, @offers = pagy(
          relation.recent.includes(:buyer, listing: :user),
          limit: page_size
        )
        set_link_header @pagy
      end

      def create
        listing = find_offerable_listing

        amount = Integer(params[:amount_cents]) rescue nil
        result = Offers::Create.call(listing: listing, buyer: current_user, amount_cents: amount)

        if result.offer
          @offer = result.offer
          render :create, status: :created
        else
          message = if result.error == :below_minimum
                      t("offers.create.errors.below_minimum",
                        min: Money.new(result.min_amount_cents, listing.currency).formatted)
          else
                      t("offers.create.errors.#{result.error}")
          end
          render_error(:unprocessable_entity, :invalid_request, message: message)
        end
      end

      private

        # Only public, approved listings accept offers; the owner is not even
        # shown the resource (404), and reserved listings pass the lookup so
        # the service can explain *why* it refuses (422) — same as the web.
        def find_offerable_listing
          listing = Listing.friendly.find(params.require(:listing_id))
          raise ActiveRecord::RecordNotFound unless listing.approved? || listing.reserved?
          raise ActiveRecord::RecordNotFound if listing.user_id == current_user.id

          listing
        end
    end
  end
end
