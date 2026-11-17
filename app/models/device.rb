# A mobile device registered for push notifications (Phase 8b). Tokens are
# stored for future push delivery — nothing sends yet. One row per
# (user, push_token); platform is "ios" or "android".
class Device < ApplicationRecord
  PLATFORMS = %w[ios android].freeze

  belongs_to :user

  validates :push_token, presence: true, length: { maximum: 4096 },
                        uniqueness: { scope: :user_id }
  validates :platform, presence: true, inclusion: { in: PLATFORMS }
end
