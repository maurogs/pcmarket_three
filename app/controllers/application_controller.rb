class ApplicationController < ActionController::Base
  include Authentication
  include Pagy::Method # reviews tab on store pages (ListingSearch paginates internally)

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  around_action :switch_locale

  helper_method :current_country_code

  private
    # The rest of the app reads the signed-in user through Current.user;
    # current_user is the classic name views and controllers prefer.
    def current_user
      Current.user
    end
    helper_method :current_user

    # Locale precedence: URL segment > signed-in user preference > default (:es).
    def switch_locale(&action)
      locale = params[:locale] || Current.user&.locale || I18n.default_locale
      I18n.with_locale(normalize_locale(locale)) do
        Pagy::I18n.locale = I18n.locale.to_s # pagination chrome ("Prev/Next/…")
        action.call
      end
    end

    def normalize_locale(locale)
      locale = locale.to_s
      I18n.available_locales.map(&:to_s).include?(locale) ? locale : I18n.default_locale
    end

    def default_url_options
      { locale: I18n.locale }
    end

    # Whitelist of ListingSearch input params (shared by listings, category
    # and store pages; the service reads only these).
    def search_params
      params.slice(:q, :category, :min_price, :max_price, :condition, :f,
                   :labels, :tags, :seller, :sort, :page)
    end

    # The cart of the current visitor: the user's own cart when signed in,
    # otherwise the guest cart keyed by a signed cookie token. `create:
    # false` (the header badge) never creates a row — guests only get a
    # cart when they add their first item.
    def current_cart(create: true)
      @current_cart ||=
        if Current.user
          Cart.for_user(Current.user)
        else
          cart = Cart.for_token(cookies.signed[:cart_token])
          if cart.nil? && create
            cart = Cart.create!
            cookies.signed.permanent[:cart_token] =
              { value: cart.token, httponly: true, same_site: :lax }
          end
          cart
        end
    end
    helper_method :current_cart

    # Item count for the header cart badge (one SUM query, and — unlike
    # current_cart — never creates a cart on a plain page view).
    def header_cart_count
      if Current.user
        CartItem.joins(:cart).where(carts: { user_id: Current.user.id }).sum(:quantity)
      else
        current_cart(create: false)&.total_quantity.to_i
      end
    end
    helper_method :header_cart_count

    # Favourite state of the signed-in user: listing_id => favorite_id, one
    # pluck per request, reused by every listing card on the page — cards
    # include the flag in their cache key so hearts render correctly without
    # N+1 queries.
    def favorites_by_listing_id
      @favorites_by_listing_id ||= Current.user ? Current.user.favorites.pluck(:listing_id, :id).to_h : {}
    end

    def favorite?(listing)
      favorites_by_listing_id.key?(listing.id)
    end
    helper_method :favorite?

    def favorite_id(listing)
      favorites_by_listing_id[listing.id]
    end
    helper_method :favorite_id

    # Wishlist mutations invalidate the memo so a re-render in the same
    # request sees fresh state.
    def forget_favorite(listing_id)
      favorites_by_listing_id.delete(listing_id) if defined?(@favorites_by_listing_id)
    end

    def header_favorite_count
      favorites_by_listing_id.size
    end
    helper_method :header_favorite_count

    # Single-country launch (Spain); the enabled Country row is the source of truth.
    def current_country_code
      @current_country_code ||= Country.enabled.order(:code).first&.code || "ES"
    end

    # Impersonation (Phase 6a admin support): while an admin "logs in as" a
    # user, the cookie session carries the impersonator's id and the current
    # user is the target. Drives the sticky red banner everywhere.
    def impersonation_target
      return unless session[:impersonated_user_id]

      @impersonation_target ||= User.find_by(id: session[:impersonated_user_id])
    end
    helper_method :impersonation_target

    BOT_USER_AGENT = /bot|crawl|spider|slurp|headless|preview|facebookexternalhit|curl|wget|python|monitor/i

    def bot_request?
      BOT_USER_AGENT.match?(request.user_agent.to_s)
    end
end
