# frozen_string_literal: true

require "test_helper"

# Every route under /api/v1 must appear in the OpenAPI spec, and every path in
# the spec must correspond to a real route. Verbs are compared too.
class Api::V1::OpenapiCoverageTest < ActionDispatch::IntegrationTest
  setup do
    @paths = YAML.load_file(Rails.root.join("public/api/v1/openapi.yaml"))["paths"]
  end

  test "every api/v1 route appears in the openapi spec" do
    missing = []
    each_route do |verb, path|
      next if @paths.dig(path, verb)

      missing << "#{verb.upcase} /api#{path}"
    end

    assert_empty missing, "Routes missing from public/api/v1/openapi.yaml: #{missing.join(', ')}"
  end

  test "every openapi path and verb corresponds to a real route" do
    actual = Set.new
    each_route { |verb, path| actual << [ verb, path ] }

    unexpected = []
    @paths.each do |path, operations|
      operations.each_key do |verb|
        next if %w[get post put patch delete].exclude?(verb)

        unexpected << "#{verb.upcase} /api#{path}" unless actual.include?([ verb, path ])
      end
    end

    assert_empty unexpected, "OpenAPI operations with no matching route: #{unexpected.join(', ')}"
  end

  test "spec is served at /api/v1/openapi with the right content type" do
    get "/api/v1/openapi"

    assert_response :ok
    assert_match %r{application/yaml}, response.media_type
  end

  test "docs page renders the redoc bundle pinned to a fixed version" do
    get "/api/v1/docs"

    assert_response :ok
    assert_includes response.body, "redoc@2.1.5"
    assert_includes response.body, "/api/v1/openapi"
  end

  private

  # Yields [verb, normalized_path] for every route under /api/v1, where the
  # path has the (.:format) suffix stripped, ":param" segments turned into
  # "{param}", and the "/api" prefix removed to match the spec's server URL.
  def each_route
    Rails.application.routes.routes.each do |route|
      spec = route.path.spec.to_s.sub("(.:format)", "")
      next unless spec.start_with?("/api/v1")

      path = spec.delete_prefix("/api").gsub(/:(\w+)/) { "{#{$1}}" }
      yield route.verb.underscore, path
    end
  end
end
