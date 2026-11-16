module Conversations
  # "Message seller": finds (or creates) the thread between the buyer and a
  # listing's seller. Idempotent — the (listing, buyer) pair is unique.
  # Refusals are returned as `Result#error`, never raised:
  #   :self    — sellers never open a thread on their own listing
  #   :blocked — a block in either direction stops new threads
  # Vacation-mode sellers are intentionally allowed to be contacted.
  class Start
    Result = Struct.new(:conversation, :error, keyword_init: true)

    def self.call(user:, listing:)
      new(user:, listing:).call
    end

    def initialize(user:, listing:)
      @user = user
      @listing = listing
    end

    def call
      return Result.new(error: :self) if listing.user_id == user.id
      return Result.new(error: :blocked) if blocked_between?(user, listing.user)

      conversation = Conversation.find_or_create_by!(
        listing: listing, buyer: user, seller_id: listing.user_id
      )
      Result.new(conversation: conversation)
    end

    private

    attr_reader :user, :listing

    def blocked_between?(a, b)
      Block.where(blocker: a, blocked: b).or(Block.where(blocker: b, blocked: a)).exists?
    end
  end
end
