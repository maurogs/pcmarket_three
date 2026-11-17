# Per-page SEO meta tags (title, description, canonical, Open Graph,
# Twitter, hreflang alternates) built on the meta-tags gem. Views call
# `set_meta` once; the layout renders everything with display_meta_tags.
module SeoHelper
  # Query params kept in canonical URLs of the browse/search pages.
  # `sort` and `page=1` are deliberately absent: they are ordering
  # variants of the same result set, not content.
  FILTER_PARAMS = %w[q category min_price max_price condition f labels tags seller].freeze
  FINDER_PARAMS = %w[game games resolution fps budget tags].freeze
  STORE_PARAMS = %w[tab].freeze

  # Campaign/tracking params stripped from every canonical + hreflang URL.
  TRACKING_PARAMS = %w[
    utm_source utm_medium utm_campaign utm_term utm_content
    gclid gclsrc dclid fbclid msclkid igclid ref src cn d ampc
  ].freeze

  # og:locale expects language_TERRITORY tags.
  OG_LOCALES = {
    es: "es_ES", en: "en_GB", fr: "fr_FR", de: "de_DE", it: "it_IT", pt: "pt_PT"
  }.freeze

  DEFAULT_OG_IMAGE = "/og-default.png".freeze

  # Site name comes from the Setting table (admin-editable), falling back
  # to the locale file so pages never render an empty name.
  def site_name
    Setting.get("site_name").to_s.presence || t("site.name")
  end

  # Single entry point for page meta tags. `title` and `description` are
  # translated per page type by the calling view; `noindex: true` opts a
  # page out of indexing (the Seo concern already did that for private
  # areas); `product:` adds the product:price OG extensions for listings.
  def set_meta(title:, description: nil, og_type: "website", og_image: nil,
               product: nil, noindex: false, canonical: nil)
    noindex ||= @seo_noindex_area
    description = seo_default_description if description.blank?
    canonical ||= seo_canonical_url
    og_image ||= DEFAULT_OG_IMAGE

    tags = {
      title: title,
      description: description,
      canonical: canonical,
      og: {
        title: title,
        description: description,
        url: canonical,
        type: og_type,
        image: seo_asset_url(og_image),
        site_name: site_name,
        locale: OG_LOCALES.fetch(I18n.locale),
        "locale:alternate" => (I18n.available_locales - [ I18n.locale ]).map { |l| OG_LOCALES.fetch(l) }
      },
      twitter: {
        card: "summary_large_image",
        title: title,
        description: description,
        image: seo_asset_url(og_image)
      }
    }
    tags[:robots] = "noindex,follow" if noindex
    # hreflang alternates only on indexable pages (6 locales + x-default).
    tags[:alternate] = alternate_locale_urls unless noindex
    if product
      tags[:product] = {
        price: { amount: format("%.2f", product.price.amount), currency: product.currency }
      }
    end
    set_meta_tags(tags)
  end

  # hreflang map: one absolute URL per available locale (same path with
  # the locale segment swapped), plus x-default -> the default locale.
  def alternate_locale_urls
    urls = I18n.available_locales.to_h do |locale|
      [ locale.to_s, absolute_seo_url(seo_path_for_locale(locale)) ]
    end
    urls["x-default"] = absolute_seo_url(seo_path_for_locale(I18n.default_locale))
    urls
  end

  # Absolute canonical URL of the current page: tracking params are always
  # stripped, filterable pages keep only their meaningful filter params,
  # and `page` survives only past the first page. The es form is always
  # unprefixed ("/es/x" canonicalizes to "/x") so each page has one URL.
  def seo_canonical_url
    absolute_seo_url(seo_path_for_locale(I18n.locale))
  end

  private

  # The current request path rewritten for another locale: the locale
  # segment is swapped (or inserted), and for the default locale it is
  # dropped entirely — es pages live at the domain root.
  def seo_path_for_locale(locale)
    segments = request.path.split("/")
    segments.delete_at(1) if segments[1].in?(I18n.available_locales.map(&:to_s))
    segments.insert(1, locale.to_s) unless locale.to_s == I18n.default_locale.to_s
    path = segments.join("/")
    path.start_with?("/") ? path : "/#{path}"
  end

  def absolute_seo_url(path)
    query = seo_query_string
    url = "#{request.protocol}#{request.host_with_port}#{path}"
    url += "?#{query}" if query.present?
    url
  end

  # public/ files (og images) are not pipeline assets: build the absolute
  # URL by hand; pass-through for already-absolute URLs.
  def seo_asset_url(path)
    return path if path.match?(%r{\Ahttps?://})

    "#{request.protocol}#{request.host_with_port}#{path}"
  end

  def seo_query_string
    params = request.query_parameters.to_h.except(*TRACKING_PARAMS)
    kept = seo_kept_params
    if kept
      params = params.slice(*kept, "page")
      params.delete("page") unless params["page"].to_i > 1
    else
      params = {}
    end
    params.to_query
  end

  # Filterable pages keep their filters (they define distinct, indexable
  # result sets); every other page is canonicalized to its bare path.
  def seo_kept_params
    case controller.controller_name
    when "listings" then controller.action_name == "index" ? FILTER_PARAMS : nil
    when "categories" then FILTER_PARAMS
    when "pc_finder_results" then FINDER_PARAMS
    when "stores" then STORE_PARAMS
    end
  end

  def seo_default_description
    descriptions = Setting.get("default_meta_description")
    (descriptions.is_a?(Hash) ? descriptions[I18n.locale.to_s] : nil).presence ||
      t("seo.default_description")
  end
end
