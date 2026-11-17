# GET /robots.txt — dynamic so the rules can react to the
# `search_engine_indexing` Setting and to the environment: anything that is
# not production (or has indexing switched off) disallows the whole site,
# which is exactly what staging should never leak into search results.
#
# Routing note: `get "robots.txt"` lives OUTSIDE the locale scope on
# purpose — robots.txt must be served at the domain root (no /es prefix).
# It is not a resource in the RESTful sense but a machine-readable
# convention with a fixed path, so the "no custom routes" rule does not
# apply here.
class RobotsController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :enforce_maintenance_mode

  def show
    render plain: rules, content_type: "text/plain"
  end

  private

  def rules
    return "User-agent: *\nDisallow: /\n" unless indexable?

    # All user-facing routes are locale-prefixed (/es/admin), so the
    # private areas are anchored with a leading wildcard; the un-prefixed
    # forms are disallowed too (the locale segment is optional in routes).
    # Search-result and filtered pages are NOT disallowed here: they carry
    # `noindex` meta tags instead, which robots.txt blocks would hide.
    lines = %w[admin sell account cart checkout conversations session
               registration passwords orders favorites notifications].flat_map do |area|
      [ "Disallow: /*/#{area}", "Disallow: /#{area}" ]
    end
    lines << "Allow: /"

    <<~ROBOTS
      User-agent: *
      #{lines.join("\n")}

      Sitemap: #{request.protocol}#{request.host_with_port}/sitemaps/sitemap.xml.gz
    ROBOTS
  end

  def indexable?
    Rails.env.production? && Setting.search_engine_indexing?
  end
end
