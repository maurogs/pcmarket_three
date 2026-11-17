# GET /cart — items grouped by seller with per-seller shipping and an
# estimated total (Carts::Summary owns those rules). Guests get a cart
# page too: their cart comes from the signed cookie token (see
# ApplicationController#current_cart). "Recommended for you" shows eight
# published listings from the cart's categories, cached per cart state.
class CartsController < ApplicationController
  allow_unauthenticated_access

  RECOMMENDED_LIMIT = 8

  def show
    @cart = current_cart
    @summary = Carts::Summary.new(@cart)
    @recommended = recommended_listings
  end

  private

  def recommended_listings
    category_ids = @summary.live_items.filter_map { |item| item.listing&.category_id }.uniq

    return [] if category_ids.empty?

    Rails.cache.fetch(
      [ "cart_recommended", @cart.id, category_ids, @cart.cart_items.maximum(:updated_at) ],
      expires_in: 30.minutes
    ) do
      Listing.published
             .where(category_id: category_ids)
             .where.not(id: @summary.live_items.filter_map { |item| item.listing_id }.uniq)
             .with_card_data
             .order(published_at: :desc, id: :desc)
             .limit(RECOMMENDED_LIMIT)
    end
  end
end
