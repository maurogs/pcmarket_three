require "test_helper"

class DemoImages::FetcherTest < ActiveSupport::TestCase
  JPEG_BYTES = ("\xFF\xD8\xFF\xE0\x00\x10JFIF\x00\x01\x01".b + ("j" * 200)).b
  GIF_BYTES = ("GIF89a" + ("\x01" * 200)).b
  SEARCH_RE = %r{api\.openverse\.org/v1/images/\?}
  CDN_RE = %r{cdn\.example\.com/}

  setup do
    @cache_dir = Pathname(Dir.mktmpdir("demo_images_fetcher"))
    @fetcher = DemoImages::Fetcher.new(cache_dir: @cache_dir)
    DemoImages::Providers::Openverse.min_call_interval = 0
  end

  teardown do
    FileUtils.remove_entry(@cache_dir)
    DemoImages::Providers::Openverse.last_call_at = nil
  end

  test "downloads a candidate and serves it from the pool cache afterwards" do
    stub_search([ "https://cdn.example.com/one.jpg" ])
    stub_download("https://cdn.example.com/one.jpg", JPEG_BYTES, "image/jpeg")

    first = @fetcher.fetch(query: "rtx 4060 graphics card", title: "MSI RTX 4060", slot: 0)
    assert_equal "openverse", first.source
    assert_equal "image/jpeg", first.content_type
    assert_equal "Anne Artist", first.attribution["creator"]
    assert File.exist?(first.path)

    # Second listing on the same query: served from the pool, no new search
    # (the search stub was allowed only once).
    second = @fetcher.fetch(query: "rtx 4060 graphics card", title: "Gigabyte RTX 4060", slot: 0)
    assert_equal "openverse", second.source
    assert_equal first.path, second.path
    assert_requested(:get, SEARCH_RE, times: 1)
  end

  test "non-image bodies are rejected by magic bytes and never cached" do
    stub_search([ "https://cdn.example.com/animated.gif" ])
    stub_download("https://cdn.example.com/animated.gif", GIF_BYTES, "image/gif")

    result = @fetcher.fetch(query: "strange gadget", title: "Strange gadget", slot: 0)

    assert_equal "placeholder", result.source
    assert_equal "image/png", result.content_type
    manifest = @cache_dir.join("strange-gadget", "manifest.json")
    assert_not manifest.exist?, "a rejected download must not create pool entries"
  end

  test "falls back to a locally rendered placeholder when every provider fails" do
    stub_request(:get, SEARCH_RE).to_return(status: 500, body: "boom")

    result = @fetcher.fetch(query: "obscure component", title: "Obscure component", slot: 0)

    assert_equal "placeholder", result.source
    assert_equal "image/png", result.content_type
    assert_nil result.attribution
    assert File.exist?(result.path)
    assert_equal 1, @fetcher.source_counts["placeholder"]
  end

  test "a failed search does not poison the query: later fetches retry it" do
    row = { "url" => "https://cdn.example.com/late.jpg", "creator" => "Anne Artist", "license" => "by",
            "foreign_landing_url" => "https://cdn.example.com" }
    stub_request(:get, SEARCH_RE)
            .to_return(status: 503, body: "quota exhausted")
            .to_return(status: 200, body: { "results" => [ row ] }.to_json,
                       headers: { "Content-Type" => "application/json" })
    stub_download("https://cdn.example.com/late.jpg", JPEG_BYTES, "image/jpeg")

    first = @fetcher.fetch(query: "flaky provider query", title: "Flaky one", slot: 0)
    assert_equal "placeholder", first.source

    second = @fetcher.fetch(query: "flaky provider query", title: "Flaky two", slot: 1)
    assert_equal "openverse", second.source, "the retry must find the recovered provider"
    assert_requested(:get, SEARCH_RE, times: 2)
  end

  private

  def stub_search(urls)
    rows = urls.map { { "url" => _1, "creator" => "Anne Artist", "license" => "by",
                        "foreign_landing_url" => _1.sub(%r{/[^/]+\z}, "") } }
    stub_request(:get, SEARCH_RE)
            .to_return(status: 200, body: { "results" => rows }.to_json,
                       headers: { "Content-Type" => "application/json" })
  end

  def stub_download(url, body, content_type)
    stub_request(:get, url).to_return(status: 200, body:, headers: { "Content-Type" => content_type })
  end
end
