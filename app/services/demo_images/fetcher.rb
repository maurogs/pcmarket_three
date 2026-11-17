# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "net/http"

module DemoImages
  # Downloads demo photos into an on-disk cache and hands the seed script a
  # local file + attribution hash ready for the Active Storage blob metadata.
  #
  # Providers are tried in order Pexels -> Pixabay -> Openverse (the first
  # two only when their API-key ENV vars are set). Each successfully
  # downloaded photo is cached under `tmp/demo_images/<query-slug>/` with a
  # `manifest.json` of attribution, so re-seeding is offline and fast. When
  # every provider fails and nothing is cached, DemoImages::Placeholder
  # renders a local PNG instead — seeding never depends on the network.
  class Fetcher
    Result = Struct.new(:path, :attribution, :source, :content_type, keyword_init: true)

    PROVIDERS = [ Providers::Pexels, Providers::Pixabay, Providers::Openverse ].freeze
    USER_AGENT = "PCMarketSeed/1.0"
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 10
    MAX_BYTES = 8.megabytes
    MAX_REDIRECTS = 3
    # Per-query pool: once this many distinct photos are cached, further
    # listings reuse them and no network call happens for that query again.
    POOL_SIZE = 6

    attr_reader :source_counts

    def initialize(cache_dir: Rails.root.join("tmp", "demo_images"))
      @cache_dir = File.expand_path(cache_dir)
      @candidates_by_query = {}
      @search_attempts = Hash.new(0)
      @failed_urls = Set.new
      @source_counts = Hash.new(0)
    end

    # Returns a Result(path:, attribution: (hash or nil), source:
    # "pexels"|"pixabay"|"openverse"|"placeholder").
    def fetch(query:, title: nil, category_label: nil, slot: 0)
      dir = File.join(@cache_dir, query.to_s.parameterize)
      FileUtils.mkdir_p(dir)
      manifest = read_manifest(dir)
      entries = manifest["entries"]

      if entries.size < POOL_SIZE && (candidate = next_candidate(query, entries))
        if (entry = download(candidate, dir))
          entries << entry
          write_manifest(dir, query:, entries:)
        else
          # Dead/oversized source URL: remember it so the same candidate
          # isn't retried for every listing in this process.
          @failed_urls << candidate[:url]
        end
      end

      result = from_cache(entries, slot, dir)
      return result if result

      placeholder(query:, title:, category_label:, slot:, dir:)
    end

    private

    def read_manifest(dir)
      path = File.join(dir, "manifest.json")
      data = File.exist?(path) ? JSON.parse(File.read(path)) : {}
      { "query" => data["query"], "entries" => Array(data["entries"]).compact }
    rescue JSON::ParserError
      { "query" => nil, "entries" => [] }
    end

    def write_manifest(dir, query:, entries:)
      File.write(File.join(dir, "manifest.json"), JSON.pretty_generate({ "query" => query, "entries" => entries }))
    end

    def from_cache(entries, slot, dir)
      return nil if entries.empty?

      entry = entries[slot % entries.size]
      path = File.join(dir, entry["file"].to_s)
      return nil unless File.exist?(path)

      @source_counts[entry["provider"]] += 1
      Result.new(path:, attribution: entry["attribution"], source: entry["provider"],
                 content_type: entry["content_type"])
    end

    def placeholder(query:, title:, category_label:, slot:, dir:)
      path = File.join(dir, format("placeholder-%s.png", Digest::SHA256.hexdigest("#{title}#{query}")[0, 12]))
      rendered = Placeholder.render(title: title.presence || query,
                                   category_label:, path:, seed: slot)
      @source_counts["placeholder"] += 1
      Result.new(path: rendered, attribution: nil, source: "placeholder", content_type: "image/png")
    end

    # Providers are searched once per query per process; candidates are
    # kept so growing the pool never repeats a search (Openverse's anonymous
    # rate limit makes re-searching expensive). A FAILED search (timeout,
    # 429) also yields [] — memoizing that would poison the query for the
    # whole run, so empty results are retried a bounded number of times and
    # only non-empty searches are memoized.
    SEARCH_RETRIES_PER_QUERY = 3

    def candidates_for(query)
      @candidates_by_query[query] ||= []
      return @candidates_by_query[query] if @candidates_by_query[query].any?

      @search_attempts[query] ||= 0
      return [] if @search_attempts[query] >= SEARCH_RETRIES_PER_QUERY

      @search_attempts[query] += 1
      @candidates_by_query[query] = PROVIDERS.flat_map do |provider|
        provider.available? ? provider.search(query, limit: 20) : []
      end
    end

    def next_candidate(query, entries)
      cached_urls = entries.map { |entry| entry["url"] }.to_set
      candidates_for(query).find { |candidate| cached_urls.exclude?(candidate[:url]) }
    end

    def download(candidate, dir)
      body = http_get(candidate[:url])
      return nil if body.nil?

      content_type = sniff_content_type(body)
      return nil if content_type.nil?

      file = format("%s-%s.%s", candidate[:provider], Digest::SHA256.hexdigest(candidate[:url])[0, 12],
                    { "image/jpeg" => "jpg", "image/png" => "png", "image/webp" => "webp" }.fetch(content_type))
      File.binwrite(File.join(dir, file), body)

      {
        "file" => file,
        "url" => candidate[:url],
        "content_type" => content_type,
        "width" => candidate[:width],
        "height" => candidate[:height],
        "provider" => candidate[:provider],
        "attribution" => {
          "creator" => candidate[:creator],
          "creator_url" => candidate[:creator_url],
          "license" => candidate[:license],
          "license_url" => candidate[:license_url],
          "source_url" => candidate[:source_url],
          "provider" => candidate[:provider]
        }
      }
    end

    def http_get(url, redirects_left: MAX_REDIRECTS)
      uri = URI.parse(url)
      return nil unless %w[http https].include?(uri.scheme)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request = Net::HTTP::Get.new(uri.request_uri, { "User-Agent" => USER_AGENT })
      body = nil
      size = 0

      http.request(request) do |response|
        case response
        when Net::HTTPRedirection
          return nil if redirects_left <= 0
          return http_get(URI.join(uri, response["location"]).to_s, redirects_left: redirects_left - 1)
        when Net::HTTPSuccess
          body = +""
          response.read_body do |chunk|
            size += chunk.bytesize
            return nil if size > MAX_BYTES
            body << chunk
          end
        else
          return nil
        end
      end

      body
    rescue StandardError => e
      Rails.logger.warn "DemoImages::Fetcher: #{e.class} downloading #{url}"
      nil
    end

    # Accepts only real images: sniff the magic bytes instead of trusting
    # Content-Type headers.
    def sniff_content_type(body)
      head = body.to_s[0, 16].to_s
      case head[0, 3]
      when "\xFF\xD8\xFF".b then "image/jpeg"
      else
        case head[0, 4]
        when "\x89PNG".b then "image/png"
        when "RIFF".b   then "image/webp" if head[8, 4] == "WEBP".b
        end
      end
    end
  end
end
