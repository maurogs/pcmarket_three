class CategoriesController < ApplicationController
  allow_unauthenticated_access
  include BrowserCaching

  # Browse a category (and its descendants) with the shared results UI.
  def show
    @category = Category.find_by!(slug: params[:id])
    # One loaded children array serves the subcategory pills and the SEO
    # links; the search shares this exact instance (preloaded associations).
    @category.children.load
    search = search_params.merge(category: @category.slug)
    @result = ListingSearch.new(search, country_code: current_country_code,
                                request: request, category: @category).call

    render "listings/index"
  end
end
