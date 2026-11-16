# Shared mapping from raw sell-form params to Listing attributes: form-shaped
# input (euro strings, category slugs, empty checkboxes, blank spec inputs)
# becomes the columns the model validates. Unparseable prices are reported
# back as :invalid so the services can surface friendly errors instead of
# silently storing 0.
module Listings
  module FormAttributes
    INVALID = :invalid_price

    module_function

    # Category picker: `category_child` wins when present (leaf first), and
    # `category_root` is the fallback. Returns [category, error_key].
    def resolve_category(root_slug, child_slug)
      slug = child_slug.presence || root_slug
      return [ nil, :blank ] if slug.blank?

      category = Category.friendly.find(slug)
      return [ nil, :not_found ] unless category&.active?

      [ category, nil ]
    rescue ActiveRecord::RecordNotFound
      [ nil, :not_found ]
    end

    # Builds the model attribute hash (everything except user/store/category/
    # photos/tags, which the services handle). Returns [attrs, invalid_prices].
    def build(raw, category:)
      attrs = {}
      attrs[:title] = raw[:title] if raw.key?(:title)
      attrs[:description] = raw[:description] if raw.key?(:description)
      attrs[:condition] = raw[:condition] if Listing.conditions.key?(raw[:condition].to_s)
      attrs[:quantity] = raw[:quantity] if raw[:quantity].present?
      attrs[:city] = raw[:city].presence if raw.key?(:city)
      attrs[:region] = raw[:region].presence if raw.key?(:region)
      attrs[:postal_code] = raw[:postal_code].presence if raw.key?(:postal_code)

      if raw.key?(:shipping_available)
        attrs[:shipping_available] = checkbox_on?(raw[:shipping_available])
      end
      if raw.key?(:local_pickup)
        attrs[:local_pickup] = checkbox_on?(raw[:local_pickup])
      end
      if raw.key?(:free_shipping)
        attrs[:free_shipping] = checkbox_on?(raw[:free_shipping])
      end

      price_attrs, invalid = price_attributes(raw, free_shipping: attrs[:free_shipping])
      attrs.merge!(price_attrs)
      attrs[:specs] = normalize_specs(raw[:specs], category) if raw.key?(:specs)
      [ attrs, invalid ]
    end

    # "599", "599.99", "1.299,99" -> integer cents. Blank -> nil, garbage -> INVALID.
    def euros_to_cents(value)
      return nil if value.nil? || value.to_s.strip.empty?

      str = value.to_s.strip.delete(" ")
      if str.match?(/\A\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?\z/)
        str = str.delete(".").sub(",", ".")
      elsif str.include?(",") && !str.include?(".") && str.match?(/\A\d+,\d{1,2}\z/)
        str = str.tr(",", ".")
      end
      amount = BigDecimal(str)
      return INVALID if amount.negative?

      (amount * 100).round
    rescue ArgumentError, TypeError
      INVALID
    end

    # Normalises submitted spec values against the category's attributes:
    # blanks are dropped, booleans and arrays are cast so the jsonb stores the
    # same shapes the search facets expect. Unknown keys are kept as submitted
    # so Listing#validate_specs can report them.
    def normalize_specs(raw_specs, category)
      return {} if raw_specs.blank?

      attributes = category ? category.all_spec_attributes.index_by(&:key) : {}
      out = {}
      raw_specs.each do |key, value|
        next if key.blank?

        attribute = attributes[key.to_s]
        cast = cast_spec_value(value, attribute)
        out[key.to_s] = cast unless cast.nil?
      end
      out
    end

    def cast_spec_value(value, attribute)
      return value unless attribute

      case attribute.input_type
      when "boolean"
        return nil if value.to_s.strip.empty? || value.nil?

        ActiveModel::Type::Boolean.new.cast(value)
      when "multi_select"
        cleaned = Array(value).map(&:to_s).reject(&:blank?)
        cleaned.presence
      else
        text = value.to_s.strip
        text.presence
      end
    end

    def seller_tag_ids(raw)
      slugs = Array(raw[:seller_tag_ids]).map(&:to_s).reject(&:blank?).uniq.first(Listing::MAX_SELLER_TAGS + 1)
      SellerTag.where(slug: slugs).order(:slug).pluck(:id)
    end

    def allow_offers_value(raw, store)
      case raw[:allow_offers]
      when "true" then true
      when "false" then false
      else store&.allow_offers_default
      end
    end

    def uploaded_photos(raw)
      Array(raw[:photos]).reject { |file| file.blank? }
    end

    # module_function: every helper below is also a module method so both
    # services can share them; keep them side-effect free.
    def price_attributes(raw, free_shipping:)
      attrs = {}
      invalid = []

      if raw.key?(:price)
        price = euros_to_cents(raw[:price])
        if price == INVALID then invalid << :price_cents else attrs[:price_cents] = price end
      end

      if raw.key?(:original_price)
        original = euros_to_cents(raw[:original_price])
        if original == INVALID
          invalid << :original_price_cents
        else
          attrs[:original_price_cents] = original
        end
      end

      if raw.key?(:shipping_price)
        if free_shipping
          attrs[:shipping_price_cents] = 0
        else
          shipping = euros_to_cents(raw[:shipping_price])
          if shipping == INVALID
            invalid << :shipping_price_cents
          else
            attrs[:shipping_price_cents] = shipping || 0
          end
        end
      end

      [ attrs, invalid ]
    end

    def checkbox_on?(value)
      %w[1 true on].include?(value.to_s)
    end
  end
end
