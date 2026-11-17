require "test_helper"

# Routing safety net for the JSON API: every route whose controller starts
# with "api/v1" must resolve to a real controller action. Catches the two
# failure modes this surface keeps hitting — a singular resource routed to a
# plural controller that was never written, and a nested namespace whose
# constant the file does not actually define.
class Api::V1::RouteActionsTest < ActionDispatch::IntegrationTest
  test "every api/v1 route resolves to a controller action" do
    unresolved = api_routes.reject { |route| route_resolves?(route) }

    assert_empty(unresolved.map do |route|
      "#{route.verb.presence || "ANY"} #{route.path.spec} -> " \
        "#{"#{route.defaults[:controller]}_controller".camelize}##{route.defaults[:action]}"
    end)
  end

  test "the api namespace exposes a sane number of routes" do
    # Guards the check itself: an accidentally narrowed scan would pass silently.
    assert_operator api_routes.size, :>=, 60
    assert api_routes.all? { |route| route.defaults[:controller].start_with?("api/v1/") }
  end

  test "the api routes stay outside the locale scope" do
    # Clients negotiate language with Accept-Language, so /es/api/v1 must not
    # resolve — a locale-prefixed duplicate would fork the cache keys.
    %w[/es /en /fr].each do |prefix|
      matched = begin
        Rails.application.routes.recognize_path("#{prefix}/api/v1/listings")
      rescue ActionController::RoutingError
        nil
      end

      assert_nil matched, "#{prefix}/api/v1/listings must not route into the API"
    end

    assert_routing "/api/v1/listings", controller: "api/v1/listings", action: "index", format: :json
    # The dashboard route is singular (OpenAPI has one seller dashboard).
    assert_routing "/api/v1/sell/dashboard", controller: "api/v1/sell/dashboards", action: "show",
                                            format: :json
  end

  private

    def route_resolves?(route)
      "#{route.defaults[:controller]}_controller".camelize.constantize
                                                            .action_methods.include?(route.defaults[:action])
    rescue NameError
      false
    end

    def api_routes
      @api_routes ||= Rails.application.routes.routes.select do |route|
        route.defaults[:controller].to_s.start_with?("api/v1")
      end
    end
end
