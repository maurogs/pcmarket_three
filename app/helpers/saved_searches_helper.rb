# Human-readable one-liner describing what a saved search filters on.
module SavedSearchesHelper
  def saved_search_filters_summary(saved_search)
    filters = saved_search.filters || {}
    parts = []

    parts << t("saved_searches.summary.quoted_query", query: saved_search.query) if saved_search.query.present?
    parts << saved_search.category.name if saved_search.category
    if filters["condition"].present?
      parts << Listing.human_attribute_name("condition/#{filters['condition']}")
    end
    parts << saved_search_price_range(filters)
    parts << Label.where(slug: filters["labels"]).pluck(:name).join(", ") if filters["labels"].present?
    if filters["seller"].present?
      parts << Store.find_by(slug: filters["seller"])&.name
    end
    parts << t("saved_searches.summary.more_filters", count: (filters.keys - %w[condition labels seller]).size) if (filters.keys - %w[condition labels seller]).any?

    parts.compact_blank.join(" · ")
  end

  private

  def saved_search_price_range(filters)
    min = filters["min_price"].presence && filters["min_price"].to_i * 100
    max = filters["max_price"].presence && filters["max_price"].to_i * 100
    return if min.nil? && max.nil?

    if min && max
      t("saved_searches.summary.price_between", min: money(min), max: money(max))
    elsif min
      t("saved_searches.summary.price_min", min: money(min))
    else
      t("saved_searches.summary.price_max", max: money(max))
    end
  end
end
