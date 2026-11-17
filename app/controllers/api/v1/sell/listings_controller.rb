module Api
  module V1
    module Sell
      # The seller's own listings in any state — every lookup runs through
      # current_user.listings, so foreign ids 404 (same discipline as the
      # web Sell::ListingsController). Creation/update delegate to
      # Listings::Create and Listings::Update; photos arrive as ActiveStorage
      # signed ids from POST /api/v1/direct_uploads, and state changes live
      # in the nested submission / archival / sale_mark resources.
      class ListingsController < BaseController
        before_action :verify_user!
        before_action :set_listing, only: %i[show update]

        def index
          scope = current_user.listings
          scope = scope.where(status: params[:status]) if params[:status].presence_in(Listing.statuses.keys)
          @pagy, @listings = pagy(scope.order(updated_at: :desc, id: :desc).with_card_data,
                                  limit: page_size)
          set_link_header @pagy
        end

        def show; end

        # Draft only — publishing is an explicit second step through
        # POST /sell/listings/:id/submission, mirroring the web form's two buttons.
        def create
          result = Listings::Create.new(current_user, form_params).call(submit: false)
          @listing = result.listing

          if result.saved?
            render :create, status: :created
          else
            render_errors(@listing)
          end
        end

        # An approved listing whose material fields change goes back to
        # pending_review — that rule is Listings::Update's, untouched here.
        def update
          result = Listings::Update.new(@listing, form_params).call(submit: false)
          @listing = result.listing

          if result.saved?
            render :update
          else
            render_errors(@listing)
          end
        end

        private

          def set_listing
            @listing = current_user.listings.friendly.find(params[:id])
          end

          def form_params
            raw = params.permit(
              :title, :description, :condition, :quantity, :price, :original_price,
              :shipping_price, :shipping_available, :free_shipping, :local_pickup,
              :allow_offers, :city, :region, :postal_code, :category_root, :category_child,
              specs: {}, photos: [], remove_photo_ids: [], seller_tag_ids: []
            ).to_h

            # The JSON contract uses ids (seller_tag_ids) and real booleans;
            # FormAttributes speaks slugs and "true"/"false" form values.
            if raw.key?(:seller_tag_ids)
              raw[:seller_tag_ids] = SellerTag.where(id: Array(raw[:seller_tag_ids])).pluck(:slug)
            end
            raw[:allow_offers] = raw[:allow_offers].to_s if raw.key?(:allow_offers)

            raw
          end

          def render_errors(listing)
            render_error(:unprocessable_entity, :invalid_request,
                         details: listing.errors.as_json(full_messages: true))
          end
      end
    end
  end
end
