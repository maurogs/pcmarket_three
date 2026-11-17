module Admin
  module SidebarHelper
    # Badged with the current pending-moderation count; cached briefly because it
    # renders on every admin request.
    def admin_pending_count
      Rails.cache.fetch("admin/pending_moderation_count", expires_in: 1.minute) do
        Listing.pending_review.count
      end
    end

    # Each entry: [section key, label i18n key, path helper, icon key]. Sections
    # group the nested action controllers under their nav entry (approvals and
    # rejections belong to the moderations queue, and so on).
    ADMIN_NAV = [
      [ "admin/dashboards", "layouts.admin.nav.dashboard", :dashboard ],
      [ "admin/moderations", "layouts.admin.nav.moderations", :moderations ],
      [ "admin/listings", "layouts.admin.nav.listings", :listings ],
      [ "admin/users", "layouts.admin.nav.users", :users ],
      [ "admin/stores", "layouts.admin.nav.stores", :stores ]
    ].freeze

    ADMIN_NAV_PATHS = {
      "admin/dashboards" => :admin_dashboard_path,
      "admin/moderations" => :admin_moderations_path,
      "admin/listings" => :admin_listings_path,
      "admin/users" => :admin_users_path,
      "admin/stores" => :admin_stores_path
    }.freeze

    ADMIN_SECTIONS = {
      "admin/dashboards" => %w[dashboards],
      "admin/moderations" => %w[moderations approvals rejections bulk_moderations],
      "admin/listings" => %w[listings unpublications],
      "admin/users" => %w[users bans impersonations],
      "admin/stores" => %w[stores verifications hidings]
    }.freeze

    def admin_active?(section)
      ADMIN_SECTIONS.fetch(section, []).include?(controller_name)
    end

    def admin_nav_item(section, label_key, icon_key, badge: nil)
      active = admin_active?(section)
      tag.li(class: "admin-rail__item#{' admin-rail__item--active' if active}") do
        link_to send(ADMIN_NAV_PATHS.fetch(section)), class: "admin-rail__link",
                aria: { current: ("page" if active) } do
          concat raw(admin_nav_icon(icon_key))
          concat tag.span(t(label_key), class: "admin-rail__label")
          concat tag.span(badge, class: "admin-rail__badge") if badge.present?
        end
      end
    end

    private

    # Tiny inline heroicons (outline) keyed by nav entry.
    def admin_nav_icon(key)
      case key
      when :dashboard
        '<svg class="h-5 w-5 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M3.75 6A2.25 2.25 0 016 3.75h2.25A2.25 2.25 0 0110.5 6v2.25a2.25 2.25 0 01-2.25 2.25H6a2.25 2.25 0 01-2.25-2.25V6zM3.75 15.75A2.25 2.25 0 016 13.5h2.25a2.25 2.25 0 012.25 2.25V18A2.25 2.25 0 018.25 20.25H6A2.25 2.25 0 013.75 18v-2.25zM13.5 6a2.25 2.25 0 012.25-2.25H18A2.25 2.25 0 0120.25 6v2.25A2.25 2.25 0 0118 10.5h-2.25a2.25 2.25 0 01-2.25-2.25V6zM13.5 15.75a2.25 2.25 0 012.25-2.25H18a2.25 2.25 0 012.25 2.25V18A2.25 2.25 0 0118 20.25h-2.25A2.25 2.25 0 0113.5 18v-2.25z"/></svg>'
      when :moderations
        '<svg class="h-5 w-5 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12c0 1.268-.63 2.39-1.593 3.068a3.745 3.745 0 01-1.043 3.296 3.745 3.745 0 01-3.296 1.043A3.745 3.745 0 0112 21c-1.268 0-2.39-.63-3.068-1.593a3.746 3.746 0 01-3.296-1.043 3.745 3.745 0 01-1.043-3.296A3.745 3.745 0 013 12c0-1.268.63-2.39 1.593-3.068a3.745 3.745 0 011.043-3.296 3.746 3.746 0 013.296-1.043A3.746 3.746 0 0112 3c1.268 0 2.39.63 3.068 1.593a3.746 3.746 0 013.296 1.043 3.745 3.745 0 011.043 3.296A3.745 3.745 0 0121 12z"/></svg>'
      when :listings
        '<svg class="h-5 w-5 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M8.25 6.75h12M8.25 12h12m-12 5.25h12M3.75 6.75h.007v.008H3.75V6.75zm.375 0a.375.375 0 11-.75 0 .375.375 0 01.75 0zM3.75 12h.007v.008H3.75V12zm.375 0a.375.375 0 11-.75 0 .375.375 0 01.75 0zm-.375 5.25h.007v.008H3.75v-.008zm.375 0a.375.375 0 11-.75 0 .375.375 0 01.75 0z"/></svg>'
      when :users
        '<svg class="h-5 w-5 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M15 19.128a9.38 9.38 0 002.625.372 9.337 9.337 0 004.121-.952 4.125 4.125 0 00-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.201-.828-3.161A4.943 4.943 0 0012 15c-1.657 0-3.16.69-4.172 1.964-.543.96-.828 2.048-.828 3.161v.003M12 12.75a3.75 3.75 0 100-7.5 3.75 3.75 0 000 7.5zm8.253 2.347a3.75 3.75 0 10-2.608-6.452M4.357 15.097a3.75 3.75 0 112.608-6.452"/></svg>'
      when :stores
        '<svg class="h-5 w-5 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M13.5 21v-7.5a.75.75 0 01.75-.75h3a.75.75 0 01.75.75V21m-4.5 0H2.36m11.14 0H18m0 0h3.64m-1.39 0V9.349m-16.5 11.651V9.35m0 0c.315-.197.685-.33 1.085-.332 1.612-.037 3.222-.14 4.816-.308.877-.098 1.762-.147 2.65-.147.889 0 1.773.049 2.65.147 1.595.168 3.204.271 4.816.308.4.002.77.135 1.085.332m-16.5 0V2.25H21v7.1z"/></svg>'
      end
    end
  end
end
