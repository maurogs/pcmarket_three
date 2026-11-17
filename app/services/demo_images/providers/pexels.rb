# frozen_string_literal: true

module DemoImages
  module Providers
    # Pexels (https://api.pexels.com) — only used when PEXELS_API_KEY is set;
    # the key goes in the `Authorization` header. Pexels allows storing
    # copies of photos under its own license; attribution (author + page
    # link) is still expected, which the seeder records on the blob.
    class Pexels < Base
      ENDPOINT = "https://api.pexels.com/v1/search"
      LICENSE = "Pexels License"
      LICENSE_URL = "https://www.pexels.com/license/"

      class << self
        def available?
          ENV["PEXELS_API_KEY"].present?
        end

        def search(query, limit: 20)
          return [] unless available?

          body = get_json(uri(query, limit), headers: { "Authorization" => ENV["PEXELS_API_KEY"] })
          return [] unless body

          Array(body["photos"]).filter_map { |row| candidate(row) }
        end

        private

        def candidate(row)
          src = row["src"] || {}
          image_url = src["large2x"] || src["original"]
          return nil if image_url.blank?

          {
            url: image_url,
            width: row["width"].to_i,
            height: row["height"].to_i,
            creator: row.dig("user", "name").presence || "Pexels",
            creator_url: row.dig("user", "url"),
            license: LICENSE,
            license_url: LICENSE_URL,
            source_url: row["url"] || image_url,
            provider: "pexels"
          }
        end

        def uri(query, limit)
          URI.join(ENDPOINT, "?query=#{CGI.escape(query)}&per_page=#{limit}&locale=en")
        end
      end
    end
  end
end
