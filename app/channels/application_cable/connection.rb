module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      set_current_user || reject_unauthorized_connection
    end

    private
      # Two ways to authenticate the WebSocket:
      #   1. API bearer token (Phase 8b) — `?token=<token>` query param or
      #      an `Authorization: Bearer <token>` header, same ApiToken rows
      #      as the JSON API. Native apps have no cookies, so this is the
      #      supported path.
      #   2. Website session cookie (fallback, unchanged).
      def set_current_user
        if (raw = bearer_credential) && (api_token = ApiToken.authenticate(raw))
          self.current_user = api_token.user
        elsif session = Session.find_by(id: cookies.signed[:session_id])
          self.current_user = session.user
        end
      end

      def bearer_credential
        request.params["token"].presence ||
          request.headers["Authorization"].to_s[/\ABearer (.+)\z/, 1].presence
      end
  end
end
