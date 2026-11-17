# Accepting a trade-in quote — the login-gated step. Stamps the signed-in
# user onto the (possibly anonymous) quote row and walks it out of `quoted`.
# A quote past its expiry self-markets as `expired` the moment anyone tries
# to accept it, so a stale offer can never be locked in.
#
#   TradeIns::Accept.call(trade_in:, user:) # => :ok | :expired | :invalid
module TradeIns
  class Accept
    def self.call(trade_in:, user:)
      return :invalid if trade_in.nil? || user.nil?
      return :invalid unless trade_in.quoted?
      # Someone else already claimed this quote row — do not overwrite.
      return :invalid if trade_in.user_id.present? && trade_in.user_id != user.id

      if trade_in.stale_quote?
        trade_in.expire!
        return :expired
      end

      trade_in.update!(user: user)
      trade_in.transition_to!(:accepted)
      :ok
    rescue TradeIn::InvalidTransition
      :invalid
    end
  end
end
