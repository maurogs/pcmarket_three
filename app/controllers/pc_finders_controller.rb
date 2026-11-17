class PcFindersController < ApplicationController
  allow_unauthenticated_access

  # Landing page with the interactive quiz. Also pre-computes one sample
  # machine per game for the "best PCs for" strip.
  def show
    @games = Performance::FpsEstimator.games.first(6)
    @game_picks = @games.index_with { |game| PcFinder::Search.sample_for(game[:slug], country_code: current_country_code) }
  end
end
