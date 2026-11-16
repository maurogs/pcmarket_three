class CategoriesController < ApplicationController
  allow_unauthenticated_access

  # Browse a category (and its descendants) with the shared results UI.
  def show
    @category = Category.find_by!(slug: params[:id])
    search = search_params.merge(category: @category.slug)
    @result = ListingSearch.new(search, country_code: current_country_code, request: request).call

    render "listings/index"
  end
end
