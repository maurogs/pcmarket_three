# Re-computes listings.performance_score for every listing.
#
#   bin/rails performance:backfill
#
# The column already exists (phase 6b) but was never populated. New/updated
# listings score themselves via Listing#refresh_performance_score; this task
# covers everything written before that hook. Safe to re-run.
namespace :performance do
  desc "Backfill listings.performance_score for scorable categories"
  task backfill: :environment do
    total = 0
    scored = 0

    Listing.find_each(batch_size: 500) do |listing|
      score = listing.scorable_category? ? Performance::Scorer.score_from_specs(listing.specs) : nil
      # update_column skips the before_save hook (which would recompute anyway).
      listing.update_column(:performance_score, score) # rubocop:disable Rails/SkipsModelValidations
      total += 1
      scored += 1 if score
    end

    puts "Performance::Scorer: #{scored} of #{total} listings scored."
  end
end
