class AddPerformanceScoreIndexToListings < ActiveRecord::Migration[8.1]
  def change
    # The PC Finder filters published gaming PCs by
    # `performance_score >= required`; scored listings are a minority so the
    # index stays partial.
    add_index :listings, :performance_score,
              where: "performance_score IS NOT NULL",
              name: "index_listings_on_performance_score"
  end
end
