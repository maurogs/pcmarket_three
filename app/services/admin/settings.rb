module Admin
  # Site settings write path (Phase 6b): validates every form field with
  # its type (email, ranges, booleans, URLs, per-locale text limits), then
  # persists each key through Setting.set. Errors come back as
  # { field => i18n error key } so the form re-renders translated messages.
  class Settings
    SOCIAL_SITES = %w[instagram tiktok youtube x discord].freeze

    class Update
      MIN_OFFER_RANGE = 0..100
      FEATURED_DAYS_RANGE = 1..90
      ANNOUNCEMENT_MAX = 280
      META_DESCRIPTION_MAX = 160

      Result = Struct.new(:errors, keyword_init: true)

      def self.call(form)
        new(form).call
      end

      def initialize(form)
        @form = form
      end

      def call
        errors = {}
        values = {}

        string_field(errors, values, "site_name", max: 100)
        email_field(errors, values, "support_email")
        string_field(errors, values, "support_phone", max: 30, allow_blank: true)
        decimal_field(errors, values, "commission_percent", range: 0..20)
        cents_field(errors, values, "featured_price_cents")
        integer_field(errors, values, "featured_days", range: FEATURED_DAYS_RANGE)
        integer_field(errors, values, "min_offer_percent", range: MIN_OFFER_RANGE)
        integer_field(errors, values, "min_public_stat", range: 0..1_000_000)
        url_field(errors, values, "blog_url")
        legal_identity_fields(errors, values)
        announcement_fields(errors, values)
        boolean_field(errors, values, "maintenance_mode")
        social_fields(errors, values)
        meta_description_fields(errors, values)

        if errors.empty?
          values.each { |key, value| Setting.set(key, value) }
          Result.new(errors: {})
        else
          Result.new(errors: errors)
        end
      end

      private

      attr_reader :form

      def raw(key)
        form[key]
      end

      def string_field(errors, values, key, max:, allow_blank: false)
        value = raw(key).to_s.strip
        if value.blank? && !allow_blank
          errors[key] = "blank"
        elsif value.length > max
          errors[key] = "too_long"
        else
          values[key] = value
        end
      end

      def email_field(errors, values, key)
        value = raw(key).to_s.strip
        if value.match?(URI::MailTo::EMAIL_REGEXP)
          values[key] = value
        else
          errors[key] = "invalid_email"
        end
      end

      # Company identity entries (Phase 7b) may be blank — the dashboard
      # shows a "Legal identity incomplete" warning instead of blocking.
      def legal_identity_fields(errors, values)
        string_field(errors, values, "legal_name", max: 150, allow_blank: true)
        string_field(errors, values, "trade_name", max: 100, allow_blank: true)
        string_field(errors, values, "tax_id", max: 30, allow_blank: true)
        string_field(errors, values, "registered_address", max: 300, allow_blank: true)
        string_field(errors, values, "mercantile_registry_data", max: 300, allow_blank: true)
        optional_email_field(errors, values, "contact_email")
        optional_email_field(errors, values, "dpo_email")
        string_field(errors, values, "phone", max: 30, allow_blank: true)
      end

      def optional_email_field(errors, values, key)
        return if raw(key).to_s.strip.empty?

        email_field(errors, values, key)
      end

      def url_field(errors, values, key)
        value = raw(key).to_s.strip
        if value.empty?
          values[key] = ""
        elsif valid_url?(value)
          values[key] = value
        else
          errors[key] = "invalid_url"
        end
      end

      def decimal_field(errors, values, key, range:)
        value = BigDecimal(raw(key).to_s.tr(",", "."))
        if value.nil? || !range.cover?(value)
          errors[key] = "out_of_range"
        else
          values[key] = value.to_f
        end
      rescue ArgumentError
        errors[key] = "invalid_number"
      end

      def integer_field(errors, values, key, range:)
        value = Integer(raw(key).to_s, 10)
        if range.cover?(value)
          values[key] = value
        else
          errors[key] = "out_of_range"
        end
      rescue ArgumentError, TypeError
        errors[key] = "invalid_number"
      end

      def cents_field(errors, values, key)
        cents = Listings::FormAttributes.euros_to_cents(raw(key))
        if cents && cents.negative?
          errors[key] = "out_of_range"
        else
          values[key] = cents || 0
        end
      end

      def boolean_field(errors, values, key)
        values[key] = ActiveModel::Type::Boolean.new.cast(raw(key))
      end

      def translated_text_field(errors, values, key, max:)
        out = {}
        I18n.available_locales.each do |locale|
          value = form.dig(key, locale.to_s).to_s.strip
          if value.length > max
            errors["#{key}.#{locale}"] = "too_long"
            return
          end
          out[locale.to_s] = value if value.present?
        end
        values[key] = out
      end

      def announcement_fields(errors, values)
        announcement = {}
        announcement["enabled"] = ActiveModel::Type::Boolean.new.cast(raw("announcement_enabled"))
        translated_text_field(errors, announcement, "announcement_text", max: ANNOUNCEMENT_MAX)
        values["announcement"] = announcement unless errors.any?
      end

      def social_fields(errors, values)
        links = {}
        Admin::Settings::SOCIAL_SITES.each do |site|
          value = form.dig("social_links", site).to_s.strip
          if value.present? && !valid_url?(value)
            errors["social_links.#{site}"] = "invalid_url"
            return
          end
          links[site] = value.presence
        end
        values["social_links"] = links
      end

      def meta_description_fields(errors, values)
        translated_text_field(errors, values, "default_meta_description", max: META_DESCRIPTION_MAX)
      end

      def valid_url?(value)
        uri = URI.parse(value)
        uri.is_a?(URI::HTTP) && uri.host.present?
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
