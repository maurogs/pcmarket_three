require "test_helper"

module SavedSearches
  class MatchNewListingTest < ActiveSupport::TestCase
    setup do
      @listing = listings(:gigabyte) # approved, Graphics Cards, 599.99 EUR, brand_new
    end

    test "creates one notification per matching saved search and returns them" do
      broad = SavedSearch.create!(user: users(:two), name: "All GPUs", category: categories(:gpus))
      exact = SavedSearch.create!(user: users(:one), name: "RTX only", category: categories(:rtx))
      SavedSearch.create!(user: users(:one), name: "Budget", filters: { "max_price" => "100" })

      matched = SavedSearches::MatchNewListing.call(@listing)

      assert_equal [ broad ], matched
      assert_equal 1, Notification.where(kind: "saved_search_match", user: users(:two)).count
      assert_equal 0, Notification.where(kind: "saved_search_match", user: users(:one)).count
    end

    test "free-text query drives matching through ListingSearch" do
      SavedSearch.create!(user: users(:two), name: "Unrelated", query: "washing machine")

      assert_empty SavedSearches::MatchNewListing.call(@listing)
    end
  end

  class SavedSearchMatchJobTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper
    include ActionMailer::TestHelper

    test "e-mails once for a user with alert searches and stamps the watermark" do
      listing = listings(:gigabyte)
      alerts_on = SavedSearch.create!(user: users(:two), name: "Alerts", category: categories(:gpus), email_alerts: true)

      assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
        perform_enqueued_jobs { SavedSearchMatchJob.perform_now(listing.id) }
      end

      assert_not_nil alerts_on.reload.last_notified_at
    end

    test "no e-mail when the search has alerts off or the user opted out" do
      listing = listings(:gigabyte)
      alerts_off = SavedSearch.create!(user: users(:two), name: "Quiet", category: categories(:gpus))
      users(:two).update!(notification_preferences: { "email_saved_search" => false })

      SavedSearchMatchJob.perform_now(listing.id)

      assert_enqueued_emails 0
      assert_equal 1, Notification.where(kind: "saved_search_match", user: users(:two)).count
      assert_nil alerts_off.reload.last_notified_at
    end
  end
end
