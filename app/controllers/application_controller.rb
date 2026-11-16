class ApplicationController < ActionController::Base
  include Authentication

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  around_action :switch_locale

  private
    # Locale precedence: URL segment > signed-in user preference > default (:es).
    def switch_locale(&action)
      locale = params[:locale] || Current.user&.locale || I18n.default_locale
      I18n.with_locale(normalize_locale(locale), &action)
    end

    def normalize_locale(locale)
      locale = locale.to_s
      I18n.available_locales.map(&:to_s).include?(locale) ? locale : I18n.default_locale
    end

    def default_url_options
      { locale: I18n.locale }
    end
end
