# Search-engine visibility defaults shared by every controller.
#
# * `robots` meta tag defaults to index,follow; controllers under an
#   area listed in NOINDEX_AREAS (plus the dynamic rules evaluated in
#   views, e.g. search results with a free-text query) get noindex,follow.
# * The same areas also carry an `X-Robots-Tag: noindex` HTTP header, so
#   the directive survives even when a page forgets the meta tag.
#
# The per-page title/description/canonical/OG tags live in
# SeoHelper#set_meta, called from the views.
module Seo
  extend ActiveSupport::Concern

  # First controller_path segment of every area search engines must never
  # index: private areas (admin/sell/account), commerce in-progress pages
  # (cart/checkout), auth pages and user-specific list/detail pages.
  NOINDEX_AREAS = %w[
    admin sell account
    carts cart_items checkouts
    sessions passwords registrations
    conversations messages blocks read_receipts
    offers acceptances declines withdrawals
    favorites saved_searches notifications notifications_reads
    orders addresses reviews reports
    trade_in_quotes trade_in_acceptances
  ].freeze

  included do
    before_action :apply_seo_defaults
    after_action :apply_robots_header
  end

  private

  def apply_seo_defaults
    @seo_noindex_area = NOINDEX_AREAS.include?(controller_path.split("/").first)
    set_meta_tags(robots: @seo_noindex_area ? "noindex,follow" : "index,follow")
  end

  def apply_robots_header
    response.headers["X-Robots-Tag"] = "noindex, follow" if @seo_noindex_area
  end
end
