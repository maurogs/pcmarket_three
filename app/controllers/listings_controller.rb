class ListingsController < ApplicationController
  allow_unauthenticated_access
  include BrowserCaching

  # The browser-only cache header (see BrowserCaching) applies to the
  # results index; show has its own per-listing conditional-GET policy.
  skip_after_action :cache_privately_for_revalidation, only: :show

  before_action :set_listing, only: :show

  # Index doubles as the search results page (see also GET /search).
  def index
    @result = run_search(search_params)
  end

  def show
    # Conditional GET: revalidate cheaply; status changes bump updated_at.
    # The page is never public, anonymous or not (see BrowserCaching): even
    # the anonymous HTML embeds a per-session CSRF token and the guest cart
    # badge, so shared caches (CDN, proxies) must not store it. Browsers
    # still get cheap body-less 304s from the ETag.
    fresh_when(etag: show_etag, last_modified: @listing.updated_at,
               public: false,
               cache_control: { max_age: 0, must_revalidate: true, private: true })
    return if performed?

    track_view if !owner_or_admin? && !bot_request?
  end

  private

  def set_listing
    listing = Listing.friendly.find(params[:id])
    # draft / pending_review / rejected / archived stay invisible to everyone
    # but the owner and admins; sold and reserved listings stay public.
    raise ActiveRecord::RecordNotFound unless listing.approved? || listing.sold? ||
                                             listing.reserved? || owner_or_admin?(listing)

    # Retitled listings: FriendlyId :history resolves the old slug, then we
    # 301 to the canonical URL (same pattern as renamed stores).
    if listing.slug != params[:id]
      redirect_to listing_path(listing), status: :moved_permanently and return
    end

    @listing = listing
  end

  def run_search(params)
    ListingSearch.new(params, country_code: current_country_code, request: request).call
  end

  # The cart part matters as much as the signed-in flag: the header badge
  # renders from the guest cart cookie / the user's cart, so without it a
  # 304 could keep a stale badge alive after a cart change.
  def show_etag
    [ I18n.locale.to_s, Current.user.present?.to_s, cart_etag_part,
      @listing.cache_key_with_version ]
  end

  def owner_or_admin?(listing = @listing)
    user = Current.user
    return false if user.nil?

    user.admin? || listing.user_id == user.id
  end

  def track_view
    ListingViewJob.perform_later(@listing.id)
  end
end
