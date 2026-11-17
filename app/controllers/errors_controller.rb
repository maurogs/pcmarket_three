# Localized static error pages (Phase 8a). Rails' ShowExceptions keeps the
# original request's status and rewrites PATH_INFO to /404, /422 or /500, so
# the locale segment of the failing URL is only visible in the
# action_dispatch.original_path env — we recover it here to render the page
# in the visitor's language.
class ErrorsController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :enforce_maintenance_mode, raise: false
  around_action :switch_locale_from_original_path

  def not_found
    render :not_found, status: :not_found, layout: "errors"
  end

  def unprocessable
    render :unprocessable, status: :unprocessable_entity, layout: "errors"
  end

  def internal_server_error
    render :internal_server_error, status: :internal_server_error, layout: "errors"
  end

  private

  attr_reader :locale

  def switch_locale_from_original_path(&action)
    original = request.env.fetch("action_dispatch.original_path", request.fullpath)
    segment = original.to_s.split("/").reject(&:empty?).first
    @locale = I18n.available_locales.map(&:to_s).include?(segment) ? segment : I18n.default_locale.to_s

    I18n.with_locale(@locale, &action)
  end
  helper_method :locale
end
