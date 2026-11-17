module Users
  # Serialises everything we hold about a user for the GDPR data export.
  class DataExport
    def self.build(user) = new(user).to_json

    def initialize(user)
      @user = user
    end

    def to_json
      JSON.pretty_generate(
        profile: profile,
        addresses: addresses,
        listings: listings,
        orders: orders,
        messages: messages,
        favorites: favorites,
        saved_searches: saved_searches
      )
    end

    private

    attr_reader :user

    def profile
      {
        username: user.username,
        email_address: user.email_address,
        first_name: user.first_name,
        last_name: user.last_name,
        phone: user.phone,
        locale: user.locale,
        created_at: user.created_at&.iso8601
      }
    end

    def addresses
      user.addresses.order(default: :desc).map do |address|
        {
          full_name: address.full_name,
          line1: address.line1,
          line2: address.line2,
          city: address.city,
          region: address.region,
          postal_code: address.postal_code,
          country_code: address.country_code,
          phone: address.phone,
          default: address.default
        }
      end
    end

    def listings
      user.listings.map do |listing|
        {
          id: listing.id,
          title: listing.title,
          description: listing.description,
          price_cents: listing.price_cents,
          currency: listing.currency,
          condition: listing.condition,
          status: listing.status,
          created_at: listing.created_at&.iso8601
        }
      end
    end

    def orders
      Order.where(buyer_id: user.id).or(Order.where(seller_id: user.id)).map do |order|
        {
          number: order.number,
          status: order.status,
          role: order.buyer_id == user.id ? "buyer" : "seller",
          total_cents: order.total_cents,
          currency: order.currency,
          created_at: order.created_at&.iso8601
        }
      end
    end

    def messages
      user.messages.map do |message|
        {
          conversation_id: message.conversation_id,
          body: message.body,
          created_at: message.created_at&.iso8601
        }
      end
    end

    def favorites
      user.favorites.includes(:listing).map do |favorite|
        {
          listing_id: favorite.listing_id,
          listing_title: favorite.listing&.title,
          created_at: favorite.created_at&.iso8601
        }
      end
    end

    def saved_searches
      user.saved_searches.map do |search|
        {
          name: search.name,
          query: search.query,
          category: search.category&.slug,
          filters: search.filters,
          email_alerts: search.email_alerts,
          created_at: search.created_at&.iso8601
        }
      end
    end
  end
end
