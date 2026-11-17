# "Report this listing" submissions (Phase 7b). One OPEN report per user
# per listing (partial unique index + validation); closing one frees the
# slot. When three open reports pile up on a live listing it goes back to
# the moderation queue and the admins get e-mail (see below).
class Report < ApplicationRecord
  class InvalidTransition < StandardError; end

  FLOOD_THRESHOLD = 3

  enum :reason, { scam: 0, prohibited: 1, wrong_info: 2, offensive: 3, other: 4 }
  enum :resolved_action, { resolved: 0, dismissed: 1 }, prefix: true

  belongs_to :listing
  belongs_to :user
  belongs_to :resolved_by, class_name: "User", optional: true

  validates :details, length: { maximum: 2000 }, allow_blank: true

  validate :not_own_listing
  # One OPEN report per (user, listing). Implemented as a custom check
  # because the details of a uniqueness validator always report :taken,
  # and callers/tests key off :already_reported. The partial unique index
  # backstops races.
  validate :no_open_duplicate

  scope :open, -> { where(resolved_at: nil) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }

  # Enum keys, for the admin filter dropdown + param validation.
  def self.reason_options
    reasons.keys
  end

  def open?
    resolved_at.nil?
  end

  # Moderation closes a report: resolved (acted on the listing) or dismissed.
  # Idempotency guard: closing twice raises rather than silently re-writing.
  def close!(action, admin:)
    raise ArgumentError, "unknown resolution #{action.inspect}" unless %w[resolved dismissed].include?(action.to_s)
    raise InvalidTransition, I18n.t("reports.already_closed") unless open?

    update!(resolved_action: action, resolved_at: Time.current, resolved_by: admin)
  end

  after_create :revalidate_flooded_listing
  after_create_commit :notify_admins_of_flag

  private

  # Sellers do not report their own listings.
  def not_own_listing
    return unless listing && user

    errors.add(:base, :not_own_listing) if listing.user_id == user.id
  end

  def no_open_duplicate
    return unless listing_id && user_id

    conflict = self.class.where(listing_id: listing_id, user_id: user_id, resolved_at: nil)
    conflict = conflict.where.not(id: id) if persisted?
    errors.add(:user_id, :already_reported) if conflict.exists?
  end

  # Third open report on a live listing: straight back to the review queue
  # (same transition material edits use). Non-approved listings are already
  # hidden from the public, so only :approved needs the trip.
  def revalidate_flooded_listing
    return unless listing.approved?
    return unless self.class.open.where(listing_id: listing_id).count >= FLOOD_THRESHOLD

    listing.request_revalidation!
    @flagged_for_rereview = true
  end

  def notify_admins_of_flag
    return unless @flagged_for_rereview

    User.admin.find_each do |admin|
      ReportMailer.with(listing: listing, recipient: admin).listing_flagged.deliver_later
    end
  end
end
