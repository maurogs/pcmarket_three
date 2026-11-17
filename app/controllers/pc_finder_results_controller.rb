class PcFinderResultsController < ApplicationController
  allow_unauthenticated_access

  def index
    @search = PcFinder::Search.new(finder_params, country_code: current_country_code, request: request)
    @results = @search.call
  end

  private

  def finder_params
    params.slice(:game, :games, :resolution, :fps, :budget, :tags, :page).permit!
  end
end
