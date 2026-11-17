module Listings
  # CSV export of the admin listings index: the filtered relation is walked
  # with find_each (keyset batching, one page of rows in memory at a time)
  # and the lines are accumulated into the string send_data ships.
  # The photo count rides along as a scalar subselect — no N+1, no bulk
  # attachment load.
  class CsvExport
    HEADERS = %w[
      id title status condition price_cents currency category country_code
      seller_id seller_username store created_at published_at featured_until
      photos_count views_count favorites_count
    ].freeze

    PHOTOS_COUNT_SQL = <<~SQL.squish
      listings.*,
      (SELECT COUNT(*) FROM active_storage_attachments a
        WHERE a.record_type = 'Listing' AND a.record_id = listings.id AND a.name = 'photos')
        AS photos_count
    SQL

    def self.build(scope)
      new(scope).to_csv
    end

    def initialize(scope)
      @scope = scope
    end

    def to_csv
      relation = scope.select(PHOTOS_COUNT_SQL)
      out = +""
      out << csv_line(HEADERS)
      relation.find_each(batch_size: 100) do |listing|
        out << "\n" << csv_line(row(listing))
      end
      out
    end

    private

    attr_reader :scope

    # Minimal RFC-4180 writer (Ruby 4 dropped csv from the default gems).
    def csv_line(fields)
      fields.map { |field| csv_field(field) }.join(",")
    end

    def csv_field(value)
      string = value.to_s
      return string unless string.match?(/[",\n\r]/)

      %("#{string.gsub('"', '""')}")
    end

    def row(listing)
      [
        listing.id, listing.title, listing.status, listing.condition,
        listing.price_cents, listing.currency, listing.category&.slug,
        listing.country_code, listing.user_id, listing.user.username,
        listing.store&.slug,
        listing.created_at.iso8601, listing.published_at&.iso8601,
        listing.featured_until&.iso8601,
        listing.photos_count, listing.views_count, listing.favorites_count
      ]
    end
  end
end
