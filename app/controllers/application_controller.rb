class ApplicationController < ActionController::Base
  include Authentication
  include Pagy::Method # reviews tab on store pages (ListingSearch paginates internally)

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  around_action :switch_locale

  helper_method :current_country_code

  private
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

    # Single-country launch (Spain); the enabled Country row is the source of truth.
    def current_country_code
      @current_country_code ||= Country.enabled.order(:code).first&.code || "ES"
    end

    BOT_USER_AGENT = /bot|crawl|spider|slurp|headless|preview|facebookexternalhit|curl|wget|python|monitor/i

    def bot_request?
      BOT_USER_AGENT.match?(request.user_agent.to_s)
    end
end
