# frozen_string_literal: true

require "net/http"
require "uri"
require "cgi"
require "json"

module DemoImages
  module Providers
    # Shared HTTP plumbing for the demo-image search providers. Each provider
    # returns candidate photo hashes:
    #   { url, width, height, creator, creator_url, license, license_url,
    #     source_url, provider }
    # Search calls never raise: network/provider errors are logged and yield
    # an empty list so DemoImages::Fetcher can move to the next provider.
    #
    # NOTE on Unsplash: deliberately NOT implemented. The Unsplash API
    # guidelines require clients to hotlink images from unsplash.com URLs
    # (and to call their `download_location` endpoint on every download);
    # neither is compatible with copying bytes into Active Storage, which is
    # how this seeder stores photos. Pexels/Pixabay/Openverse all permit
    # storing copies with attribution, so the pipeline uses those instead.
    class Base
      USER_AGENT = "PCMarketSeed/1.0"
      OPEN_TIMEOUT = 10
      # Search endpoints (Openverse) regularly answer in ~10 s under load;
      # a tight timeout turns working searches into empty candidate lists.
      READ_TIMEOUT = 25

      class << self
        # Subclass entry point: candidates for a query, best first.
        def search(query, limit: 20)
          raise NotImplementedError
        end

        # Present only when the provider's ENV API key is configured.
        def available?
          true
        end

        private

        def get_json(uri, headers: {})
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = OPEN_TIMEOUT
          http.read_timeout = READ_TIMEOUT

          request = Net::HTTP::Get.new(uri.request_uri, { "User-Agent" => USER_AGENT }.merge(headers))
          response = http.request(request)
          unless response.is_a?(Net::HTTPSuccess)
            Rails.logger.warn "DemoImages #{name}: HTTP #{response.code} for #{uri}"
            return nil
          end

          JSON.parse(response.body)
        rescue StandardError => e
          Rails.logger.warn "DemoImages #{name}: #{e.class}: #{e.message}"
          nil
        end
      end
    end
  end
end
