module ListingsHelper
  CURRENCY_UNITS = Money::UNITS

  # Options shown before the "Show more" expander in a facet group.
  FACET_PREVIEW = 6

  # Integer cents -> locale-formatted currency (es: "1.299,00 €", en: "€1,299.00").
  def money(cents, currency = "EUR")
    code = currency.presence || "EUR"
    number_to_currency(BigDecimal(Integer(cents)) / 100,
                       unit: CURRENCY_UNITS.fetch(code, code), precision: 2)
  end

  # Translated display name for a spec option value ("amd" -> "AMD").
  # Falls back to the raw value when the attribute is free text.
  def spec_value_label(attribute, value)
    key = attribute.is_a?(SpecAttribute) ? attribute.key : attribute.to_s
    names = spec_option_names[[ key, value.to_s ]]
    return value.to_s if names.blank?

    names[I18n.locale.to_s].presence || names["en"].presence || value.to_s
  end

  # Five rating stars (filled up to the rounded average) + aria label.
  def stars(rating, classes: "size-4")
    value = rating.to_f.clamp(0.0, 5.0)
    glyphs = (1..5).map do |i|
      tag.svg(
        raw('<path d="m12 3 2.7 5.6 6.1.8-4.5 4.2 1.2 6L12 16.8 6.5 19.6l1.2-6L3.2 9.4l6.1-.8L12 3Z"/>'),
        class: "#{classes} shrink-0 #{value >= i - 0.25 ? "fill-amber-400 text-amber-400" : "fill-none text-border"}",
        viewBox: "0 0 24 24", stroke: "currentColor", "stroke-width": 1.2,
        "stroke-linejoin": "round", "aria-hidden": true
      )
    end
    tag.span(safe_join(glyphs),
             class: "inline-flex items-center gap-0.5", role: "img",
             "aria-label": t("helpers.stars.label", value: ("%.1f" % value)))
  end

  # Pagy series navigation, styled by the .series-nav component classes.
  def results_pagination(pagy)
    raw(pagy.series_nav)
  end

  # Removable chips for every filter in play: [label, url-without-that-filter].
  def applied_filter_chips(result)
    filters = result.filters
    chips = []

    if filters[:q].present?
      chips << [ t("listings.results.chip_query", query: filters[:q]), url_without_filter(type: :q) ]
    end
    if filters[:min_cents]
      chips << [ t("listings.results.chip_min", price: money(filters[:min_cents])), url_without_filter(type: :min) ]
    end
    if filters[:max_cents]
      chips << [ t("listings.results.chip_max", price: money(filters[:max_cents])), url_without_filter(type: :max) ]
    end
    if (category = filters[:category])
      chips << [ category.name, url_without_category(category) ]
    end
    filters[:conditions].each do |value|
      chips << [ Listing.human_attribute_name("condition/#{value}"),
                 url_without_filter(type: :condition, value: value) ]
    end
    filters[:specs].each do |key, values|
      values.each do |value|
        chips << [ "#{spec_attribute_label(key)}: #{spec_value_label(key, value)}",
                   url_without_filter(type: :spec, key: key, value: value) ]
      end
    end
    filters[:labels].each do |slug|
      chips << [ label_name(slug), url_without_filter(type: :labels, value: slug) ]
    end
    filters[:tags].each do |slug|
      chips << [ seller_tag_name(slug), url_without_filter(type: :tags, value: slug) ]
    end
    if (seller = filters[:seller])
      chips << [ seller.name, url_without_filter(type: :seller) ]
    end

    chips
  end

  # Checkbox rows for one spec facet: [value, label, count] in the attribute's
  # own option order (popular options first). Options with no results are
  # hidden unless they are currently selected.
  def facet_options(attribute, result)
    selected = Array(result.filters[:specs][attribute.key])
    counts = result.facets[attribute.key] || {}

    rows =
      if attribute.input_type_boolean?
        [ [ "true", boolean_value_label(true), counts["true"].to_i ],
          [ "false", boolean_value_label(false), counts["false"].to_i ] ]
      else
        attribute.spec_options.map do |option|
          [ option.value, spec_value_label(attribute, option.value), counts[option.value].to_i ]
        end
      end

    rows.select { |value, _label, count| count.positive? || selected.include?(value) }
  end

  # Same shape for the facets that come from listing columns (labels, seller tags).
  def facet_options_for_column(facet_key, param, result)
    selected = Array(result.filters[param])
    counts = result.facets[facet_key] || {}

    counts.keys.sort.filter_map do |slug|
      count = counts[slug].to_i
      next if count.zero? && !selected.include?(slug)

      [ slug, facet_key == "label" ? label_name(slug) : seller_tag_name(slug), count ]
    end
  end

  def condition_label(listing)
    Listing.human_attribute_name("condition/#{listing.condition}")
  end

  # Translated display name for a spec attribute ("gpu_chipset" -> "Chipset").
  def spec_attribute_label(attribute)
    key = attribute.is_a?(SpecAttribute) ? attribute.key : attribute.to_s
    t("specs.attributes.#{key}", default: attribute.try(:name).presence || key.humanize)
  end

  # Label for a boolean spec value (true -> "Yes").
  def boolean_value_label(value)
    value ? t("helpers.boolean.yes") : t("helpers.boolean.no")
  end

  # Spec key/value pairs in the attributes' own position order, unknown keys last.
  def sorted_spec_pairs(listing)
    positions = SpecAttribute.ordered.index_by(&:key)
    listing.specs.to_a.sort_by do |key, _value|
      [ positions.key?(key) ? 0 : 1, positions[key]&.position.to_i, key.to_s ]
    end
  end

  # Display text for one raw spec value (arrays, booleans and option labels).
  def spec_value_text(key, value)
    case value
    when Array then safe_join(value.map { |v| spec_value_label(key, v) }, ", ")
    when true, false then boolean_value_label(value)
    else spec_value_label(key, value)
    end
  end

  # Label for a listing label / seller tag slug, resolved through the DB record.
  def label_name(slug)
    label_records[slug.to_s]&.name || slug.to_s.humanize
  end

  def seller_tag_name(slug)
    seller_tag_records[slug.to_s]&.name || slug.to_s.humanize
  end

  # Estimated delivery window: 2 to 5 business days from today.
  def estimated_delivery_label
    from = business_days_from(2)
    to = business_days_from(5)
    t("listings.show.delivery_between",
      from: l(from, format: :delivery), to: l(to, format: :delivery))
  end

  # Breadcrumb chain for a category, root first (categories are 3 levels deep).
  def breadcrumb_categories(category)
    ids = category.self_and_ancestor_ids
    by_id = Category.where(id: ids).index_by(&:id)
    depth = ->(node) do
      steps = 0
      while (node = node.parent_id && by_id[node.parent_id])
        steps += 1
      end
      steps
    end
    ids.filter_map { |id| by_id[id] }.sort_by(&depth)
  end

  def verified_badge(store, classes: "size-4")
    return unless store&.verified?

    tag.span(class: "inline-flex items-center text-primary",
             title: t("stores.verified"), aria: { label: t("stores.verified") }) do
      inline_icon :shield, classes: classes
    end
  end

  # --- card / gallery photo tags (lazy-loaded, explicit dimensions) ----------

  def listing_photo_tag(listing, variant: :card, alt: listing.title)
    photo = listing.photos.first
    if photo
      size = photo_dimensions(variant)
      image_tag(variant_url(photo, variant),
                alt: alt, loading: "lazy", decoding: "async",
                width: size[0], height: size[1],
                class: "size-full object-cover")
    else
      photo_placeholder_tag(alt)
    end
  end

  # Extra HTML options (e.g. `class:`) are merged into the image tag, so
  # callers can restyle the thumbnail instead of relying on the gallery default.
  def photo_variant_tag(photo, variant: :gallery, alt: nil, sizes: nil, **html_options)
    size = photo_dimensions(variant)
    image_tag(variant_url(photo, variant),
              **{ alt: alt || photo.filename.to_s, loading: "lazy", decoding: "async",
                  width: size[0], height: size[1], class: "size-full object-contain" }
                .merge(html_options))
  end

  def photo_placeholder_tag(alt)
    tag.svg(raw('<rect x="3" y="5" width="18" height="14" rx="1.5"/><circle cx="9" cy="10" r="1.6"/><path d="m5 17 4.5-4.5L12 15l3-3 4 4"/>'),
            viewBox: "0 0 24 24", fill: "none", stroke: "currentColor",
            "stroke-width": 1.2, "stroke-linecap": "round", "stroke-linejoin": "round",
            class: "mx-auto size-1/3 text-border dark:text-slate-700", aria: { hidden: true })
  end

  private

  # Small dictionary tables, loaded once per request and indexed by slug.
  def label_records
    @label_records ||= Label.all.index_by(&:slug)
  end

  def seller_tag_records
    @seller_tag_records ||= SellerTag.all.index_by(&:slug)
  end

  # `n` business days from today, skipping weekends.
  def business_days_from(n)
    date = Date.current
    remaining = n
    while remaining > 0
      date += 1
      remaining -= 1 unless date.saturday? || date.sunday?
    end
    date
  end

  # URL that drops the category filter. Category pages carry the category in
  # the path (/c/slug), so there the results move to the generic listings path
  # while the other filters are kept.
  def url_without_category(category)
    query = request.query_parameters.deep_dup
    query["category"] = nil
    query["page"] = nil

    if request.path == category_path(category)
      listings_path(query.compact_blank)
    else
      url_for(query.compact_blank)
    end
  end

  # URL for the current request minus one applied filter (removable chips).
  def url_without_filter(type:, key: nil, value: nil)
    query = request.query_parameters.deep_dup
    query["page"] = nil

    case type
    when :q      then query["q"] = nil
    when :min    then query["min_price"] = nil
    when :max    then query["max_price"] = nil
    when :seller then query["seller"] = nil
    when :category then query["category"] = nil
    when :condition, :labels, :tags
      query[type.to_s] = (Array(query[type.to_s]) - [ value ]).presence
    when :spec
      filters = query["f"]
      if filters.is_a?(Hash)
        filters[key] = Array(filters[key]) - [ value ]
        filters.delete_if { |_k, v| Array(v).empty? }
        query["f"] = filters.presence
      end
    end

    url_for(query.compact_blank)
  end

  def variant_url(photo, variant)
    photo.variant(**Listing::PHOTO_VARIANTS.fetch(variant.to_sym))
  end

  def photo_dimensions(variant)
    Listing::PHOTO_VARIANTS.fetch(variant.to_sym).fetch(:resize_to_limit)
  end

  # SpecOption names for the whole table, preloaded once per request.
  def spec_option_names
    @spec_option_names ||=
      SpecOption.includes(:spec_attribute)
                .index_by { |option| [ option.spec_attribute.key, option.value ] }
                .transform_values(&:names)
  end
end
