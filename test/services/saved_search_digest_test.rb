require "test_helper"

class SavedSearchDigestTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  # Absolute delivery counts below: start from a clean box.
  setup { ActionMailer::Base.deliveries.clear }

  setup do
    @user = users(:two)
    @search = SavedSearch.create!(user: @user, name: "Quiet GPUs", category: categories(:gpus))
  end

  def create_match(listing)
    Notification.create!(user: @user, kind: "saved_search_match",
                         payload: { "saved_search_id" => @search.id, "listing_id" => listing.id })
  end

  test "one e-mail per user covering the unsent matches, then the watermark moves" do
    create_match(listings(:gigabyte))
    create_match(listings(:as_new))

    assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
      perform_enqueued_jobs { SavedSearchDigest.new.run }
    end

    assert_equal 1, ActionMailer::Base.deliveries.size
    assert_not_nil @search.reload.last_notified_at
    assert_empty Notification.unsent_saved_search_matches(@search)

    # A second run sends nothing: the matches were already covered.
    SavedSearchDigest.new.run
    assert_equal 1, ActionMailer::Base.deliveries.size
  end

  test "users opted out of saved-search e-mail keep their matches pending" do
    create_match(listings(:gigabyte))
    @user.update!(notification_preferences: { "email_saved_search" => false })

    SavedSearchDigest.new.run

    assert_enqueued_emails 0
    assert_equal 1, Notification.unsent_saved_search_matches(@search).count
    assert_nil @search.reload.last_notified_at
  end
end
