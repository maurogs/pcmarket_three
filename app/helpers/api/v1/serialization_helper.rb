module Api
  module V1
    # Serialization primitives shared by the Jbuilder views: Money triples,
    # absolute photo/logo variant URLs (400px card + 1200px full), absolute
    # web URLs and the notification link mapping (mirrors
    # NotificationsHelper#notification_link).
    module SerializationHelper
      def money_json(money)
        return nil if money.nil?

        { cents: money.cents, currency: money.currency, formatted: money.formatted }
      end

      # Nullable price columns (original_price, shipping_price) serialize as
      # null rather than Money.new(nil).
      def listing_money(listing, field)
        cents = listing.public_send(field)
        cents.nil? ? nil : money_json(Money.new(cents, listing.currency))
      end

      # Both rendered variants of a photo's first attachment (cards use
      # :card, detail galleries :full). Absolute URLs as required by the
      # OpenAPI contract.
      def listing_photos_json(listing)
        listing.photos.map { |photo| photo_json(photo) }
      end

      def listing_photo_json(listing)
        first = listing.photos.first
        first && photo_json(first)
      end

      def photo_json(attachment)
        # Iterating listing.photos yields attachment records, which delegate
        # missing methods to their blob — and neither has #attached? (that
        # lives on the Attached proxy / model). Persisted attachment + blob
        # is the real precondition for building variants.
        return nil unless attachment.persisted? && attachment.blob&.persisted?

        {
          card: polymorphic_url(attachment.variant(:card)),
          full: polymorphic_url(attachment.variant(:gallery))
        }
      end

      def store_logo_json(store)
        return nil unless store&.logo&.attached? && store.logo.persisted?

        polymorphic_url(store.logo.variant(**Store::LOGO_VARIANTS.fetch(:card)))
      end

      def avatar_json(user)
        return nil unless user.avatar.attached? && user.avatar.persisted?

        polymorphic_url(user.avatar.variant(**User::AVATAR_VARIANTS.fetch(:thumb)))
      end

      # Pagination meta per the OpenAPI contract (Pagy 43 Offset:
      # page/limit/count/pages), rendered by every list view.
      def pagination_meta(pagy)
        { page: pagy.page, per_page: pagy.limit, total: pagy.count, total_pages: pagy.pages }
      end

      # Facet buckets as [{value:, count:}] arrays keyed by attribute. Listing
      # Search counts condition by its enum ordinal (a column), so the ordinal is
      # translated back to the enum name the contract (and the filter param) uses.
      def facets_json(facets)
        facets.to_h do |key, buckets|
          [ key, buckets.map { |value, count| { value: facet_value_for(key, value), count: count } } ]
        end
      end

      def facet_value_for(key, value)
        key.to_s == "condition" ? Listing.conditions.key(value.to_i).to_s : value.to_s
      end

      # Echo of the applied filters as scalars (associations collapse to slugs),
      # so a client can round-trip what it sent without parsing objects.
      def search_filters_json(filters)
        {
          q: filters[:q],
          category: filters[:category]&.slug,
          min_price_cents: filters[:min_cents],
          max_price_cents: filters[:max_cents],
          conditions: filters[:conditions],
          specs: filters[:specs],
          labels: filters[:labels],
          tags: filters[:tags],
          seller: filters[:seller]&.slug,
          sort: filters[:sort]
        }
      end

      def listing_web_url(listing)
        listing_url(listing)
      end

      def store_web_url(store)
        store_url(store)
      end

      # Absolute web URL for a notification row — same target the web inbox
      # links to (see NotificationsHelper#notification_link).
      def notification_url_for(notification)
        payload = notification.payload

        case notification.kind
        when "new_message"
          conversation_id = payload["conversation_id"] and conversation_url(conversation_id)
        when "new_offer", "offer_accepted"
          offers_url
        when "price_drop", "saved_search_match", "listing_submitted",
             "listing_approved", "listing_rejected"
          listing = Listing.find_by(id: payload["listing_id"]) and listing_url(listing)
        when /\Aorder_/
          order_id = payload["order_id"] and order_url(order_id)
        end
      end

      # Query the saved search was made with, as web browse URL params
      # (SavedSearch#search_params feeds the same shape as the browse form).
      def saved_search_results_url(saved_search)
        listings_url(saved_search.search_params.presence || {})
      end
    end
  end
end
