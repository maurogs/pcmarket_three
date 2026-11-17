# Shared plumbing for the /api/v1 request specs: bearer headers (one real
# ApiToken per user, issued through the model so digests stay honest), JSON
# body parsing and a query counter used as the N+1 guard on list endpoints.
module ApiV1TestHelper
  JSON_HEADERS = { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }.freeze

  # Tokens are issued once per user per test: ApiToken.authenticate stamps
  # last_used_at, so re-using one keeps the request count down.
  def api_token_for(user)
    @api_tokens ||= {}
    @api_tokens[user.id] ||= ApiToken.issue_for(user)
  end

  # Requests default to the user set by `auth_as`; pass user: nil to send no
  # Authorization header at all.
  def auth_as(user)
    @api_user = user
  end

  # Pins the exact plaintext token a test received (e.g. from POST /session)
  # so revocation can be proven end to end.
  def use_token(user, raw)
    @api_user = user
    @api_tokens ||= {}
    @api_tokens[user.id] = raw
  end

  def json_api_headers(user: @api_user)
    headers = JSON_HEADERS.dup
    headers["Authorization"] = "Bearer #{api_token_for(user)}" if user
    headers
  end

  def json_body
    JSON.parse(response.body, symbolize_names: true)
  end

  # Every verb takes `auth_as:` so a test can switch identity inline; passing
  # nil sends no Authorization header, and omitting it keeps the last one.
  def get_json(path, auth_as: :keep, headers: nil, params: nil)
    get path, params: params, headers: request_headers(auth_as, headers)
  end

  def post_json(path, payload = nil, auth_as: :keep, headers: nil, params: nil)
    post_json_for :post, path, payload, auth_as, headers, params
  end

  def patch_json(path, payload = nil, auth_as: :keep, headers: nil, params: nil)
    post_json_for :patch, path, payload, auth_as, headers, params
  end

  def put_json(path, payload = nil, auth_as: :keep, headers: nil, params: nil)
    post_json_for :put, path, payload, auth_as, headers, params
  end

  def delete_json(path, auth_as: :keep, headers: nil, params: nil)
    delete path, params: params, headers: request_headers(auth_as, headers)
  end

  private

    def request_headers(auth_as, headers)
      @api_user = auth_as unless auth_as == :keep
      headers || json_api_headers
    end

    # Both call styles work: a positional payload (`post_json path, {a: 1}`)
    # and the `params:` keyword, which is how the older suites read.
    def post_json_for(verb, path, payload, auth_as, headers, params)
      body = payload || params
      body = body.is_a?(String) ? body : body&.to_json
      send verb, path, params: body,
                headers: request_headers(auth_as, headers).merge("CONTENT_TYPE" => "application/json")
    end

  public

  # N+1 guard: counts sql.active_record events issued by the block, ignoring
  # the bookkeeping Rails itself does (transactions, schema, cache table).
  # Query-cache hits (payload[:cached], a Rails 8.1 per-connection cache) are
  # counted: they still fan out one event per call site, so an N+1 loop shows
  # up in the count even when the same request ran moments earlier.
  def api_query_count
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_, _, _, _, payload|
      name = payload[:name].to_s
      next if %w[SCHEMA TRANSACTION CACHE].include?(name.upcase)
      next if payload[:sql].to_s.match?(/BEGIN|COMMIT|ROLLBACK|pg_|sqlite_/)

      count += 1
    end

    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include ApiV1TestHelper
end
