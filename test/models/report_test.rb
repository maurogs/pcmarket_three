require "test_helper"

# Listing reports (Phase 7b). One OPEN report per user per listing; three
# open reports on a live listing push it back to the review queue and every
# admin gets an e-mail. close! is the only way out and refuses to fire twice.
class ReportTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup { @listing = listings(:gigabyte) }

  def report_for(user, **attrs)
    Report.create!(listing: @listing, user: user, reason: :scam, **attrs)
  end

  test "a valid report on someone else's listing is accepted" do
    report = report_for(users(:two), reason: :wrong_info, details: "Specs look copied")

    assert_predicate report, :valid?
    assert_predicate report, :open?
    assert_nil report.resolved_at
  end

  test "a second OPEN report from the same user on the same listing is rejected" do
    report_for(users(:two))

    duplicate = Report.new(listing: @listing, user: users(:two), reason: :other)

    assert_not duplicate.valid?
    assert_includes duplicate.errors.details[:user_id].map { |d| d[:error] }, :already_reported
  end

  test "a closed report frees the slot for the same user" do
    first = report_for(users(:two))
    first.close!("resolved", admin: users(:admin))

    assert Report.create!(listing: @listing, user: users(:two), reason: :other)
  end

  test "you cannot report your own listing" do
    own = Report.new(listing: @listing, user: users(:one), reason: :other)

    assert_not own.valid?
    assert_includes own.errors.details[:base].map { |d| d[:error] }, :not_own_listing
  end

  test "details longer than 2000 characters are rejected" do
    assert_not Report.new(listing: @listing, user: users(:two), reason: :other,
                          details: "x" * 2001).valid?
  end

  test "close! records action, time and admin" do
    report = report_for(users(:two))
    report.close!("dismissed", admin: users(:admin))

    assert_not_predicate report.reload, :open?
    assert report.resolved_action_dismissed?
    assert_equal users(:admin), report.resolved_by
    assert_not_nil report.resolved_at
  end

  test "close! raises on an already closed report and on unknown actions" do
    report = report_for(users(:two))
    report.close!("resolved", admin: users(:admin))

    assert_raise(Report::InvalidTransition) { report.close!("dismissed", admin: users(:admin)) }
    assert_raise(ArgumentError) { report.close!("half_resolved", admin: users(:admin)) }
  end

  test "the third open report re-queues the listing and e-mails every admin" do
    admins_before = User.admin.count
    assert_enqueued_emails 0 do
      report_for(users(:two))
      assert_predicate @listing.reload, :approved?
      report_for(users(:admin))
      assert_predicate @listing.reload, :approved?
    end

    report_for(extra_reporter)
    assert_predicate @listing.reload, :pending_review?
    assert_enqueued_emails admins_before
  end

  test "flood on a listing that is not live does not trip a transition" do
    sold = listings(:sold)
    %w[two admin].each do |name|
      Report.create!(listing: sold, user: users(name.to_sym), reason: :other)
    end
    Report.create!(listing: sold, user: extra_reporter, reason: :other)

    assert_predicate sold.reload, :sold?
    assert_enqueued_emails 0
  end

  test "below the flood threshold nothing is re-queued and no e-mail flies" do
    report_for(users(:two))
    report_for(users(:admin))

    assert_predicate @listing.reload, :approved?
    assert_enqueued_emails 0
  end

  private

  def extra_reporter
    @extra_reporter ||= User.create!(email_address: "third@example.com", username: "third",
                                     first_name: "Third", last_name: "Reporter",
                                     password: "passwordpassword", locale: "en")
  end
end
