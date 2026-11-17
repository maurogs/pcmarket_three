require "test_helper"

class Phase5MailersTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  # This file counts absolute deliveries, so start from a clean box even if
  # another test in the same worker delivered mail.
  setup { ActionMailer::Base.deliveries.clear }

  test "price drop mail is skipped when the user opted out" do
    user = users(:two)
    user.notification_preferences = { "email_price_drop" => false }
    user.save!

    opted_out = PriceDropMailer.with(user: user.reload, listing: listings(:gigabyte)).price_drop.message
    assert_kind_of ActionMailer::Base::NullMail, opted_out
    assert_empty ActionMailer::Base.deliveries

    user.update!(notification_preferences: { "email_price_drop" => true })
    PriceDropMailer.with(user: user.reload, listing: listings(:gigabyte)).price_drop.deliver_now
    assert_equal 1, ActionMailer::Base.deliveries.size
    assert_equal user.email_address, ActionMailer::Base.deliveries.last.to.first
  end

  test "saved search mailers honour the channel preference" do
    user = users(:two)

    # Default preferences are ON: the instant match mail is built and sent.
    match = SavedSearchMailer.with(user: user, listing: listings(:gigabyte)).match_found
    assert_not_kind_of ActionMailer::Base::NullMail, match.message
    match.deliver_now
    assert_equal 1, ActionMailer::Base.deliveries.size

    digest = SavedSearchMailer.with(user: user.reload, listings: [ listings(:gigabyte) ]).digest
    assert_match "1", digest.subject

    user.update!(notification_preferences: { "email_saved_search" => false })
    assert_kind_of ActionMailer::Base::NullMail,
                   SavedSearchMailer.with(user: user.reload, listing: listings(:gigabyte)).match_found.message
    assert_kind_of ActionMailer::Base::NullMail,
                   SavedSearchMailer.with(user: user.reload, listings: [ listings(:gigabyte) ]).digest.message
  end

  test "deleted users never receive mail" do
    Users::Anonymize.call(users(:two))
    user = users(:two).reload

    assert_kind_of ActionMailer::Base::NullMail,
                   PriceDropMailer.with(user: user, listing: listings(:gigabyte)).price_drop.message
    assert_kind_of ActionMailer::Base::NullMail,
                   SavedSearchMailer.with(user: user, listing: listings(:gigabyte)).match_found.message
  end
end
