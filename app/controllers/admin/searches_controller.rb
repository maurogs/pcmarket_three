module Admin
  class SearchesController < BaseController
    def show
      @query = params[:q].to_s.strip
      @result = @query.length >= 2 ? Admin::GlobalSearch.call(@query) : nil
    end
  end
end
