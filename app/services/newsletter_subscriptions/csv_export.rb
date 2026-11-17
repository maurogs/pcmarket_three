module NewsletterSubscriptions
  # CSV export of the newsletter list (admin). Formula-safe: CsvBuilder
  # prefixes spreadsheet-hostile cells with a single quote — the e-mails are
  # user-supplied text and could start with =, + or -.
  class CsvExport
    HEADERS = %w[id email locale confirmed_at created_at].freeze

    def self.build(scope)
      out = +""
      out << CsvBuilder.line(HEADERS)
      scope.find_each(batch_size: 100) do |subscription|
        out << "\n" << CsvBuilder.line(
          [ subscription.id, subscription.email, subscription.locale,
            subscription.confirmed_at&.iso8601, subscription.created_at.iso8601 ]
        )
      end
      out
    end
  end
end
