module Api
  module V1
    # Shared foundation for every /api/v1 endpoint: bearer-token auth, the
    # uniform error envelope ({ error: { code, message, details } }),
    # Accept-Language locale selection, per-token rate limiting, and the
    # pagination helpers (meta object + Link header) shared by all list
    # endpoints. Controllers stay thin — business rules live in the same
    # service objects the web app uses.
    class BaseController < ActionController::API
      include Pagy::Method
      # ActionController::API skips the translation helper Base gets, but every
      # error envelope and transition message is an I18n key.
      include AbstractController::Translation

      # Jbuilder views need the serialization primitives explicitly —
      # ActionController::API does not auto-include app helpers.
      helper Api::V1::SerializationHelper

      before_action :set_locale
      before_action :authenticate_token!

      # 300 requests/minute per token (per IP while anonymous). The test env
      # uses the memory store (see config), so this is exercisable in tests.
      rate_limit to: 300, within: 1.minute,
                 by: -> { "api_v1:#{Current.api_token&.id || request.remote_ip}" },
                 with: -> { render_error(:too_many_requests, :rate_limited) }

      rescue_from ActiveRecord::RecordNotFound do
        render_error(:not_found, :not_found)
      end

      rescue_from ActiveRecord::RecordInvalid do |error|
        render_error(:unprocessable_entity, :invalid_request,
                     details: error.record.errors.as_json(full_messages: true))
      end

      rescue_from ActionController::ParameterMissing do |error|
        render_error(:bad_request, :invalid_request, details: { param: error.param })
      end

      rescue_from Api::V1::Forbidden do
        render_error(:forbidden, :forbidden)
      end

      # Listing state-machine refusals (submit/archive/sale_mark) come back
      # as 409s; the model message is already localized.
      rescue_from Listing::InvalidTransition do |error|
        render_error(:conflict, :invalid_transition, message: error.message)
      end

      private
        # Bearer-authenticated user for the current request (nil on public
        # endpoints without a token). Call sites use current_user everywhere.
        def current_user
          Current.user
        end

        # Guards endpoints that must never run without a resolved user even
        # though authenticate_token! already guarantees one — kept explicit
        # so skipping the auth callback can never expose a nil-user path.
        def verify_user!
          render_error(:unauthorized, :unauthorized) if current_user.nil?
        end

        # Shared ?limit= for paginated list endpoints (Pagy `limit:`).
        def page_size
          requested = params[:limit].to_i
          requested.between?(1, 100) ? requested : 20
        end

        # Absolute web URLs embedded in payloads point at the client's
        # negotiated language (same contract as the web app).
        def default_url_options
          { locale: I18n.locale }
        end

        # Accept-Language negotiation: the first supported language wins,
        # es (the default locale) otherwise.
        def set_locale
          I18n.locale = preferred_locale
        end

        def preferred_locale
          header = request.env["HTTP_ACCEPT_LANGUAGE"].to_s
          requested = header.split(",").filter_map { |part| part.split(";").first.presence }
          requested.lazy.filter_map do |tag|
            base = tag.downcase.split("-").first
            I18n.available_locales.find { |locale| locale.to_s == base }
          end.first || I18n.default_locale
        end

        # Bearer token → ApiToken → user. Public controllers skip this
        # callback entirely. Banned accounts are refused with 403.
        def authenticate_token!
          raw = bearer_token
          return render_error(:unauthorized, :unauthorized) if raw.blank?

          token = ApiToken.authenticate(raw)
          return render_error(:unauthorized, :unauthorized) if token.nil?

          user = token.user
          if user.banned?
            Current.api_token = token
            return render_error(:forbidden, :banned)
          end

          Current.api_token = token
          Current.user = user
        end

        def bearer_token
          header = request.headers["Authorization"].to_s
          match = header.match(/\ABearer (.+)\z/)
          match && match[1].presence
        end

        # Public endpoints: a token is optional, but when one is sent we
        # still resolve it so owners/admins see their own private listings.
        def authenticate_token_if_present
          raw = bearer_token
          return if raw.blank?

          token = ApiToken.authenticate(raw)
          return if token.nil? || token.user.banned?

          Current.api_token = token
          Current.user = token.user
        end

        # Country scoping for search endpoints: optional ?country= (only
        # enabled codes), otherwise the first enabled country — the web
        # equivalent of ApplicationController#current_country_code.
        def api_country_code
          code = params[:country].presence
          if code && Country.enabled.exists?(code: code)
            code
          else
            Country.enabled.order(:code).first&.code || "ES"
          end
        end

        def render_error(status, code, message: nil, details: nil)
          render json: {
            error: {
              code: code.to_s,
              message: message.presence || t("api.errors.#{code}"),
              details: details
            }
          }, status: status
        end

        def set_link_header(pagy)
          base = "#{request.base_url}#{request.path}"
          page_url = lambda do |page|
            "#{base}?#{request.query_parameters.except('page').merge('page' => page).to_query}"
          end

          links = [ "<#{page_url.call(1)}>; rel=\"first\"" ]
          links << "<#{page_url.call(pagy.page - 1)}>; rel=\"prev\"" if pagy.page > 1
          links << "<#{page_url.call(pagy.page + 1)}>; rel=\"next\"" if pagy.page < pagy.pages
          links << "<#{page_url.call(pagy.pages)}>; rel=\"last\""
          response.set_header "Link", links.join(", ")
        end
    end
  end
end
