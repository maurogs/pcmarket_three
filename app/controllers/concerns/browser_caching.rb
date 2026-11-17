# frozen_string_literal: true

# Shared HTTP cache headers for 200 HTML responses (category browse,
# listings index, PC Finder results). These pages must NEVER be marked
# `public`: every rendered page embeds per-session data even for anonymous
# visitors — the `csrf_meta_tags` token and the guest cart badge
# (`header_cart_count`, read from the signed `cart_token` cookie). A CDN or
# shared proxy storing such a page would hand one visitor's CSRF token and
# cart badge to another, breaking their POSTs (e.g. the footer newsletter
# form) and leaking cart state.
#
# So HTML caching is browser-only:
#
#   Cache-Control: private, max-age=0, must-revalidate
#
# Repeat views are still cheap: browsers revalidate against the
# ETag/Last-Modified headers the controllers set with `fresh_when`, and a
# matching revalidation is a body-less 304. The page ETags include the
# signed-in flag and the guest-cart state so a 304 can never serve a stale
# CSRF token or cart badge.
#
# Include in anonymous-cacheable controllers; applied after the action so the
# header wins over anything a renderer might have set.
module BrowserCaching
  extend ActiveSupport::Concern

  included do
    after_action :cache_privately_for_revalidation
  end

  private

  def cache_privately_for_revalidation
    return unless response.status == 200

    response.cache_control[:public] = false
    response.cache_control[:private] = true
    response.cache_control[:max_age] = 0
    response.cache_control[:must_revalidate] = true
  end
end
