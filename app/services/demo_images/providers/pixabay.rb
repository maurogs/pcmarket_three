# frozen_string_literal: true

module DemoImages
  module Providers
    # Pixabay (https://pixabay.com/api/) — only used when PIXABAY_API_KEY is
    # set. Pixabay requires downloading images rather than hotlinking them
    # (which is exactly what the Fetcher does before attaching them through
    # Active Storage), and always filters through `safesearch=true`.
    class Pixabay < Base
      ENDPOINT = "https://pixabay.com/api/"
      LICENSE = "Pixabay Content License"
      LICENSE_URL = "https://pixabay.com/service/license-summary/"

      class << self
        def available?
          ENV["PIXABAY_API_KEY"].present?
        end

        def search(query, limit: 20)
          return [] unless available?

          body = get_json(uri(query, limit))
          return [] unless body

          Array(body["hits"]).filter_map { |row| candidate(row) }
        end

        private

        def candidate(row)
          image_url = row["largeImageURL"] || row["webformatURL"]
          return nil if image_url.blank?

          {
            url: image_url,
            width: row["imageWidth"].to_i,
            height: row["imageHeight"].to_i,
            creator: row["user"].presence || "Pixabay",
            creator_url: nil, # the API does not expose user profile URLs
            license: LICENSE,
            license_url: LICENSE_URL,
            source_url: row["pageURL"] || image_url,
            provider: "pixabay"
          }
        end

        def uri(query, limit)
          URI.join(ENDPOINT,
                   "?key=#{CGI.escape(ENV["PIXABAY_API_KEY"].to_s)}" \
                   "&q=#{CGI.escape(query)}&safesearch=true&per_page=#{limit}")
        end
      end
    end
  end
end
