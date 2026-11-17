# frozen_string_literal: true

module DemoImages
  module Providers
    # Openverse (https://api.openverse.org) — no API key needed. Anonymous
    # access is rate limited, so calls are throttled to one every
    # MIN_CALL_INTERVAL seconds and the requests ask for
    # `license_type=commercial,modification` only.
    class Openverse < Base
      ENDPOINT = "https://api.openverse.org/v1/images/"
      MIN_CALL_INTERVAL = 3 # seconds; anonymous rate-limit courtesy
      # Client-side backstop for the `commercial,modification` filter: keep
      # only permissive licenses (by, by-sa, cc0, pdm…), never NC/ND.
      ALLOWED_LICENSES = %w[by by-sa cc0 pdm zero].freeze

      class << self
        # Test seam: `min_call_interval = 0` skips the sleep.
        attr_accessor :min_call_interval, :last_call_at

        def search(query, limit: 20)
          wait_for_rate_limit!
          body = get_json(uri(query, limit))
          return [] unless body

          Array(body["results"]).filter_map { |row| candidate(row) }
        end

        private

        def candidate(row)
          license = row["license"].to_s.downcase
          return nil unless ALLOWED_LICENSES.include?(license)
          return nil if row["url"].blank?

          version = row["license_version"].presence
          {
            url: row["url"],
            width: row["width"].to_i,
            height: row["height"].to_i,
            creator: row["creator"].presence || "Unknown",
            creator_url: row["creator_url"],
            license: [ license.upcase, version ].compact.join(" "),
            license_url: row["license_url"],
            source_url: row["foreign_landing_url"] || row["url"],
            provider: "openverse"
          }
        end

        def uri(query, limit)
          URI.join(ENDPOINT, "?q=#{CGI.escape(query)}" \
                             "&license_type=commercial,modification&page_size=#{limit}")
        end

        def wait_for_rate_limit!
          self.min_call_interval ||= MIN_CALL_INTERVAL
          now = Time.now
          if last_call_at && (elapsed = now - last_call_at) < min_call_interval
            sleep(min_call_interval - elapsed)
          end
          self.last_call_at = Time.now
        end
      end
    end
  end
end
