require "test_helper"

module Users
  class DataExportTest < ActiveSupport::TestCase
    test "JSON contains every bucket of personal data" do
      user = users(:two)
      Favorite.create!(user: user, listing: listings(:gigabyte))
      search = SavedSearch.create!(user: user, name: "GPUs", query: "gpu", email_alerts: true)
      user.addresses.create!(full_name: "Ada Lovelace", line1: "Calle 1", city: "Madrid",
                             postal_code: "28001", country_code: "ES", default: true)

      payload = JSON.parse(Users::DataExport.build(user))

      assert_equal %w[profile addresses listings orders messages favorites saved_searches], payload.keys
      assert_equal user.email_address, payload.dig("profile", "email_address")
      assert_includes payload["listings"].map { |l| l["id"] }, listings(:as_new).id
      numbers = payload["orders"].index_by { |o| o["number"] }
      assert_equal %w[PCM-2025-000001 PCM-2025-000002].sort, numbers.keys.sort
      assert_equal "seller", numbers["PCM-2025-000001"]["role"]
      assert_equal "buyer", numbers["PCM-2025-000002"]["role"]
      assert_equal 1, payload["favorites"].count { |f| f["listing_id"] == listings(:gigabyte).id }
      assert_equal search.name, payload["saved_searches"].first["name"]
      assert payload["addresses"].first["default"]
    end
  end

  class DataExportJobTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    test "attaches the JSON export and mails the signed link" do
      user = users(:two)

      assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
        perform_enqueued_jobs { DataExportJob.perform_now(user) }
      end

      assert user.reload.export.attached?
      assert_equal "application/json", user.export.content_type
      json = JSON.parse(user.export.download)
      assert_equal user.email_address, json.dig("profile", "email_address")

      body = ActionMailer::Base.deliveries.last.text_part.body.decoded
      assert_includes body, "/rails/active_storage/blobs/redirect/"
    end
  end
end
