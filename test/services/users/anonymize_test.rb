require "test_helper"

module Users
  class AnonymizeTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      @user = users(:two)
      Favorite.create!(user: @user, listing: listings(:gigabyte))
      SavedSearch.create!(user: @user, name: "Doomed search")
      @user.addresses.create!(full_name: "Ada Lovelace", line1: "Calle 1", city: "Madrid",
                              postal_code: "28001", country_code: "ES")
    end

    test "refuses while orders are still open" do
      Order.create!(number: "PCM-TEST-OPEN-1", buyer: @user, seller: users(:one),
                    status: :pending_payment, currency: "EUR", subtotal_cents: 1_000,
                    shipping_cents: 0, total_cents: 1_000)

      assert_raises(Users::Anonymize::OpenOrderError) { Users::Anonymize.call(@user) }
      assert_equal @user.email_address, @user.reload.email_address
    end

    test "wipes personal data and related records, hides the store" do
      user = users(:two)
      ApiToken.issue_for(user, name: "cli")
      token = user.api_tokens.reload.first
      store = user.store

      Users::Anonymize.call(user)

      user.reload
      assert user.deleted?
      assert_equal "deleted-#{user.id}@invalid", user.email_address
      assert_equal "deleted-#{user.id}", user.username
      assert_nil user.first_name
      assert_nil user.phone
      assert store.reload.hidden?
      assert_empty user.addresses
      assert_empty user.favorites
      assert_empty user.saved_searches
      assert_empty user.api_tokens
      assert_empty user.sessions
      assert_nil ApiToken.find_by(id: token.id)
      user.listings.each { |listing| assert_includes %w[archived sold], listing.status }
    end

    test "anonymized users cannot receive e-mail" do
      Users::Anonymize.call(users(:two))
      assert_not users(:two).reload.wants_email?("orders")
    end

    test "avatar and GDPR export attachments are purged after the commit" do
      user = users(:two)
      user.avatar.attach(io: StringIO.new("avatar-bytes"), filename: "me.jpg", content_type: "image/jpeg")
      user.export.attach(io: StringIO.new(%({"personal":true})), filename: "export.json",
                         content_type: "application/json")
      user.reload

      Users::Anonymize.call(user)

      assert_equal 2, enqueued_jobs.count { |job| job["job_class"] == "ActiveStorage::PurgeJob" }
      perform_enqueued_jobs

      user.reload
      assert_not user.avatar.attached?
      assert_not user.export.attached?
    end
  end
end
