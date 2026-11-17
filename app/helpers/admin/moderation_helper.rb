module Admin
  module ModerationHelper
    # Title/description words that commonly mark a listing as spammy, scammy
    # or prohibited. The list itself lives in the locale files
    # (admin.moderations.show.risky_words.words) so each language flags the
    # phrasings that matter in its own market.
    def admin_risky_word_matches(listing)
      words = I18n.t("admin.moderations.show.risky_words.words", default: [])
      text = "#{listing.title}\n#{listing.description}".downcase

      words.select do |word|
        Regexp.new("\\b#{Regexp.escape(word.downcase)}\\b").match?(text)
      end
    end

    # "price vs category median" summary for the moderation page:
    # [key, magnitude] with key in above/below/on, or nil without a median.
    def admin_price_vs_median(listing, median_cents)
      return if median_cents.nil? || median_cents.zero?

      diff = (listing.price_cents - median_cents).fdiv(median_cents) * 100
      key = if diff.abs < 5 then "on"
      elsif diff.positive? then "above"
      else "below"
      end
      [ key, diff.abs.round ]
    end
  end
end
