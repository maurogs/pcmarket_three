# JSON-LD structured data (schema.org). Builders return plain Hashes;
# `json_ld_tag` renders them with ActiveSupport's to_json, which escapes
# "<", ">" and "&" as \u003c, \u003e and \u0026 — so titles containing
# `</script>` can never break out of the tag. Do NOT add json_escape/ERB
# escaping on top: it corrupts the JSON the crawlers parse.
module JsonLdHelper
  SCHEMA_CONTEXT = "https://schema.org".freeze
  AVAILABILITY = { "sold" => "SoldOut" }.freeze # approved/reserved => InStock
  # Listing conditions -> schema.org itemCondition tokens.
  ITEM_CONDITIONS = {
    "brand_new" => "NewCondition",
    "open_box" => "UsedCondition",
    "used_like_new" => "UsedCondition",
    "used_good" => "UsedCondition",
    "for_parts" => "DamagedCondition"
  }.freeze

  def json_ld_tag(*data)
    payload =
      if data.size == 1
        data.first.merge("@context" => SCHEMA_CONTEXT)
      else
        { "@context" => SCHEMA_CONTEXT, "@graph" => data }
      end
    # ActiveSupport's to_json (escape_html_entities_in_json = true by
    # default) already encodes every "<" as \u003c, so "</script>" can never
    # appear literally and the JSON can be emitted raw. No extra escaping.
    script = payload.to_json
    tag.script(script.html_safe, type: "application/ld+json",
                                 data: { json_ld: payload.dig("@graph", 0, "@type") || payload["@type"] })
  end

  def organization_json_ld
    {
      "@type" => "Organization",
      "name" => site_name,
      "url" => root_url,
      "logo" => seo_asset_url("/icon-512.png")
    }.merge(same_as_json_ld)
  end

  # Sitelinks search box: the box POSTs to the public listings search.
  def web_site_json_ld
    {
      "@type" => "WebSite",
      "name" => site_name,
      "url" => root_url,
      "inLanguage" => SeoHelper::OG_LOCALES.fetch(I18n.locale),
      "potentialAction" => {
        "@type" => "SearchAction",
        "target" => {
          "@type" => "EntryPoint",
          "urlTemplate" => listings_url + "?q={search_term_string}"
        },
        "query-input" => "required name=search_term_string"
      }
    }
  end

  # crumbs: [[name, url?]] — the last crumb (current page) has no URL.
  def breadcrumb_json_ld(crumbs)
    {
      "@type" => "BreadcrumbList",
      "itemListElement" => crumbs.each_with_index.map { |(name, url), i|
        { "@type" => "ListItem", "position" => i + 1, "name" => name, "url" => url }.compact
      }
    }
  end

  def product_json_ld(listing)
    {
      "@type" => "Product",
      "name" => listing.title,
      "description" => listing.description.to_s.presence || listing.title,
      "sku" => listing.id.to_s,
      "url" => listing_url(listing),
      "image" => listing_image_urls(listing),
      "brand" => brand_json_ld(listing.specs),
      "offers" => offer_json_ld(listing)
    }.compact
  end

  # AggregateRating for store pages — only once there are visible reviews.
  def store_json_ld(store)
    node = {
      "@type" => "Organization",
      "name" => store.name,
      "url" => store_url(store),
      "description" => store.description.to_s.presence
    }.compact
    if store.reviews_count.positive?
      node["aggregateRating"] = {
        "@type" => "AggregateRating",
        "ratingValue" => store.rating_average,
        "reviewCount" => store.reviews_count
      }
    end
    node
  end

  # ItemList for the first page of a category's results (capped at 24).
  def item_list_json_ld(listings)
    {
      "@type" => "ItemList",
      "itemListElement" => listings.first(24).each_with_index.map { |listing, i|
        {
          "@type" => "ListItem", "position" => i + 1, "name" => listing.title,
          "url" => listing_url(listing)
        }
      }
    }
  end

  # entries: [[question, answer], ...]
  def faq_json_ld(entries)
    {
      "@type" => "FAQPage",
      "mainEntity" => entries.map { |question, answer|
        {
          "@type" => "Question", "name" => question,
          "acceptedAnswer" => { "@type" => "Answer", "text" => answer }
        }
      }
    }
  end

  private

  def listing_image_urls(listing)
    urls = listing.photos.map { |photo| seo_asset_url(variant_url(photo, :gallery)) }
    urls.presence || [ seo_asset_url(SeoHelper::DEFAULT_OG_IMAGE) ]
  end

  def offer_json_ld(listing)
    {
      "@type" => "Offer",
      "url" => listing_url(listing),
      "price" => format("%.2f", listing.price.amount),
      "priceCurrency" => listing.currency,
      "availability" => AVAILABILITY.fetch(listing.status, "InStock"),
      "itemCondition" => "https://schema.org/#{ITEM_CONDITIONS.fetch(listing.condition, "UsedCondition")}",
      "seller" => seller_json_ld(listing)
    }
  end

  def seller_json_ld(listing)
    if listing.store
      { "@type" => "Organization", "name" => listing.store.name, "url" => store_url(listing.store) }
    else
      { "@type" => "Person", "name" => listing.user.display_name }
    end
  end

  # First brand-ish spec (GPUs/CPU-first) as the Product brand; absent
  # when the listing carries no brand spec (accessories, games, ...).
  def brand_json_ld(specs)
    return nil unless specs.is_a?(Hash)

    value = specs["gpu_brand"].presence || specs["cpu_brand"].presence ||
            specs["device_brand"].presence || specs["motherboard_brand"].presence ||
            specs["memory_brand"].presence || specs["psu_brand"].presence
    return nil if value.blank?

    { "@type" => "Brand", "name" => value.to_s.humanize }
  end

  def same_as_json_ld
    links = Setting.get("social_links")
    links = links.values.compact_blank if links.is_a?(Hash)
    links = [] unless links.is_a?(Array)
    links.any? ? { "sameAs" => links } : {}
  end
end
