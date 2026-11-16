class ApiToken < ApplicationRecord
  TOKEN_LENGTH = 32

  belongs_to :user

  validates :token_digest, presence: true, uniqueness: true
  validates :name, presence: true, length: { maximum: 100 }

  scope :active, lambda {
    where("expires_at IS NULL OR expires_at > ?", Time.current)
  }

  # Returns the plaintext token exactly once; only its SHA256 digest is stored.
  def self.issue_for(user, name: "API token", expires_at: nil)
    raw = SecureRandom.alphanumeric(TOKEN_LENGTH)
    create!(user: user, name: name, expires_at: expires_at,
            token_digest: digest_for(raw))
    raw
  end

  def self.digest_for(raw)
    Digest::SHA256.hexdigest(raw)
  end

  # Finds the matching active token and stamps last_used_at, or nil.
  def self.authenticate(raw)
    return if raw.blank?

    token = active.find_by(token_digest: digest_for(raw))
    token&.touch(:last_used_at)
    token
  end

  def expired?
    !expires_at.nil? && expires_at <= Time.current
  end
end
