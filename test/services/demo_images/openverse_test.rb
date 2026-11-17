require "test_helper"

class DemoImages::OpenverseTest < ActiveSupport::TestCase
  ENDPOINT_RE = %r{api\.openverse\.org/v1/images/\?}

  setup do
    # Test seam: skip the 3 s anonymous-rate-limit sleep.
    DemoImages::Providers::Openverse.min_call_interval = 0
  end

  teardown do
    DemoImages::Providers::Openverse.last_call_at = nil
  end

  test "search parses rows into candidate hashes with attribution" do
    stub_search({ "results" => [
      { "url" => "https://cdn.example/img.jpg", "width" => 1200, "height" => 800,
        "creator" => "Anne Artist", "creator_url" => "https://example/anne",
        "license" => "by-sa", "license_version" => "4.0",
        "license_url" => "https://creativecommons.org/licenses/by-sa/4.0",
        "foreign_landing_url" => "https://flickr.example/photos/1" }
    ] })

    candidates = DemoImages::Providers::Openverse.search("rtx graphics card", limit: 20)

    assert_equal 1, candidates.size
    candidate = candidates.first
    assert_equal "https://cdn.example/img.jpg", candidate[:url]
    assert_equal 1200, candidate[:width]
    assert_equal "Anne Artist", candidate[:creator]
    assert_equal "BY-SA 4.0", candidate[:license]
    assert_equal "https://flickr.example/photos/1", candidate[:source_url]
    assert_equal "openverse", candidate[:provider]
  end

  test "search asks only for commercial, modification-friendly licenses" do
    stub_request(:get, ENDPOINT_RE)
            .with(query: hash_including("license_type" => "commercial,modification", "page_size" => "20"))
            .to_return(status: 200, body: { "results" => [] }.to_json)

    DemoImages::Providers::Openverse.search("graphics card")

    assert_requested(:get, ENDPOINT_RE,
                     query: hash_including("license_type" => "commercial,modification"))
  end

  test "non-commercial licenses and rows without a url are dropped" do
    stub_search({ "results" => [
      { "url" => "https://cdn.example/nc.jpg", "license" => "by-nc" },
      { "url" => "https://cdn.example/nd.jpg", "license" => "by-nd" },
      { "url" => nil, "license" => "by" },
      { "url" => "https://cdn.example/ok.jpg", "license" => "CC0" }
    ] })

    candidates = DemoImages::Providers::Openverse.search("anything")

    assert_equal [ "https://cdn.example/ok.jpg" ], candidates.map { _1[:url] }
    assert_equal "Unknown", candidates.first[:creator]
  end

  test "API errors return an empty list instead of raising" do
    stub_request(:get, ENDPOINT_RE).to_return(status: 500, body: "boom")

    assert_empty DemoImages::Providers::Openverse.search("anything")
  end

  private

  def stub_search(body)
    stub_request(:get, ENDPOINT_RE).to_return(status: 200, body: body.to_json,
                                              headers: { "Content-Type" => "application/json" })
  end
end
