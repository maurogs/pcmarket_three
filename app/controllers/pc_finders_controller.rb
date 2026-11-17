class PcFindersController < ApplicationController
  allow_unauthenticated_access

  # Landing page with the interactive quiz. Also pre-computes one sample
  # machine per game for the "best PCs for" strip.
  def show
    @games = Performance::FpsEstimator.games.first(6)
    @game_picks = load_game_picks
  end

  private

  # One PcFinder::Search per game costs ~6 queries each, and the strip only
  # renders title/price: cache just the pick ids per country + catalogue
  # freshness (rebuilt at most once per 10 minutes), then load every pick in
  # one query with the card includes.
  def load_game_picks
    ids = Rails.cache.fetch(
      [ "pc_finder/game_picks", current_country_code, Listing.maximum(:updated_at) ],
      expires_in: 10.minutes
    ) do
      # Pause the N+1 scan on a cold strip: rebuilding it runs one Search
      # per game, but that is a bounded cache rebuild (once per country and
      # catalogue change, every 10 min at most) — not a per-row view N+1.
      NPlusOnePause.call do
        @games.index_with { |game| PcFinder::Search.sample_for(game[:slug], country_code: current_country_code)&.id }
      end
    end
    picks = Listing.where(id: ids.values.compact).with_card_data.index_by(&:id)
    ids.transform_values { |id| picks[id] }
  end
end
