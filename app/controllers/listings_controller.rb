class ListingsController < ApplicationController
  allow_unauthenticated_access

  before_action :set_listing, only: :show

  # Index doubles as the search results page (see also GET /search).
  def index
    @result = run_search(search_params)
  end

  def show
    # Conditional GET: revalidate cheaply; status changes bump updated_at.
    # Shared caches (CDN, proxies) may only store what is identical for everyone:
    # an anonymous hit on a listing the public can see. Signed-in responses carry
    # a personalised header, and owners/admins also see draft/pending/rejected
    # listings, so everything else stays private.
    shared_cacheable = Current.user.nil? && (@listing.approved? || @listing.sold?)
    fresh_when(etag: show_etag, last_modified: @listing.updated_at,
               public: shared_cacheable,
               cache_control: { max_age: 0, must_revalidate: true, private: !shared_cacheable })
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

  def show_etag
    [ I18n.locale.to_s, Current.user.present?.to_s, @listing.cache_key_with_version ]
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
