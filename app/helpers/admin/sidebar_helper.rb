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
      [ "admin/trade_ins", "layouts.admin.nav.trade_ins", :trade_ins ],
      [ "admin/listings", "layouts.admin.nav.listings", :listings ],
      [ "admin/orders", "layouts.admin.nav.orders", :orders ],
      [ "admin/disputes", "layouts.admin.nav.disputes", :disputes ],
      [ "admin/reviews", "layouts.admin.nav.reviews", :reviews ],
      [ "admin/users", "layouts.admin.nav.users", :users ],
      [ "admin/stores", "layouts.admin.nav.stores", :stores ],
      [ "admin/categories", "layouts.admin.nav.categories", :categories ],
      [ "admin/spec_attributes", "layouts.admin.nav.spec_attributes", :spec_attributes ],
      [ "admin/labels", "layouts.admin.nav.labels", :labels ],
      [ "admin/seller_tags", "layouts.admin.nav.seller_tags", :seller_tags ],
      [ "admin/countries", "layouts.admin.nav.countries", :countries ],
      [ "admin/feature_flags", "layouts.admin.nav.feature_flags", :feature_flags ],
      [ "admin/reports", "layouts.admin.nav.reports", :reports ],
      [ "admin/contact_messages", "layouts.admin.nav.contact_messages", :contact_messages ],
      [ "admin/settings", "layouts.admin.nav.settings", :settings ],
      [ "admin/legal_pages", "layouts.admin.nav.legal_pages", :legal_pages ],
      [ "admin/newsletter_subscriptions", "layouts.admin.nav.newsletter", :newsletter ],
      [ "admin/audit_logs", "layouts.admin.nav.audit_logs", :audit_logs ]
    ].freeze

    ADMIN_NAV_PATHS = {
      "admin/dashboards" => :admin_dashboard_path,
      "admin/moderations" => :admin_moderations_path,
      "admin/trade_ins" => :admin_trade_ins_path,
      "admin/listings" => :admin_listings_path,
      "admin/orders" => :admin_orders_path,
      "admin/disputes" => :admin_disputes_path,
      "admin/reviews" => :admin_reviews_path,
      "admin/users" => :admin_users_path,
      "admin/stores" => :admin_stores_path,
      "admin/categories" => :admin_categories_path,
      "admin/spec_attributes" => :admin_spec_attributes_path,
      "admin/labels" => :admin_labels_path,
      "admin/seller_tags" => :admin_seller_tags_path,
      "admin/countries" => :admin_countries_path,
      "admin/feature_flags" => :admin_feature_flags_path,
      "admin/reports" => :admin_reports_path,
      "admin/contact_messages" => :admin_contact_messages_path,
      "admin/settings" => :edit_admin_settings_path,
      "admin/legal_pages" => :admin_legal_pages_path,
      "admin/newsletter_subscriptions" => :admin_newsletter_subscriptions_path,
      "admin/audit_logs" => :admin_audit_logs_path
    }.freeze

    ADMIN_SECTIONS = {
      "admin/dashboards" => %w[dashboards],
      "admin/moderations" => %w[moderations approvals rejections bulk_moderations],
      "admin/trade_ins" => %w[trade_ins],
      "admin/listings" => %w[listings unpublications],
      "admin/orders" => %w[orders notes],
      "admin/disputes" => %w[disputes resolutions],
      "admin/reviews" => %w[reviews],
      "admin/users" => %w[users bans impersonations],
      "admin/stores" => %w[stores verifications hidings],
      "admin/categories" => %w[categories positions category_spec_attributes],
      "admin/spec_attributes" => %w[spec_attributes spec_options bulk_options spec_option_merges],
      "admin/labels" => %w[labels],
      "admin/seller_tags" => %w[seller_tags],
      "admin/countries" => %w[countries],
      "admin/feature_flags" => %w[feature_flags],
      "admin/reports" => %w[reports report_resolutions report_dismissals],
      "admin/contact_messages" => %w[contact_messages],
      "admin/settings" => %w[settings],
      "admin/legal_pages" => %w[legal_pages],
      "admin/newsletter_subscriptions" => %w[newsletter_subscriptions],
      "admin/audit_logs" => %w[audit_logs]
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

    # Tiny inline heroicons (outline) keyed by nav entry. Phase 6b entries
    # use simple hand-drawn 24x24 strokes (same stroke width and size as
    # the heroicons above) to keep the helper readable.
    SIMPLE_NAV_ICONS = {
      orders: "M8.25 6.75h7.5M8.25 12h7.5m-7.5 5.25h4.5M6 3.75h12a1.5 1.5 0 011.5 1.5v13.5a1.5 1.5 0 01-1.5 1.5H6a1.5 1.5 0 01-1.5-1.5V5.25A1.5 1.5 0 016 3.75z",
      disputes: "M12 3.75L21 19H3l9-15.25zM12 10v4m0 2.5v.01",
      reviews: "M12 4.5l2.3 4.7 5.2.8-3.7 3.6.9 5.1-4.7-2.5-4.7 2.5.9-5.1L4.5 10l5.2-.8L12 4.5z",
      categories: "M3.75 6.75A1.5 1.5 0 015.25 5.25h3.6l1.9 2.25h8.25a1.5 1.5 0 011.5 1.5v8.25a1.5 1.5 0 01-1.5 1.5h-13.5a1.5 1.5 0 01-1.5-1.5v-10.5z",
      spec_attributes: "M5 7.5h14M5 12h14M5 16.5h14M8.25 5.25v4.5m7.5-1.5v4.5m-6 1.5v4.5",
      labels: "M7.5 6.75h.01M4.5 4.5h7l8.5 8.5-7 7-8.5-8.5v-7zM9 15.5l5.5-5.5",
      seller_tags: "M7.5 3.75h9a1.5 1.5 0 011.5 1.5v15l-6-3-6 3v-15a1.5 1.5 0 011.5-1.5z",
      trade_ins: "M4.5 8.25h15l-2.7-2.7m2.7 2.7l-2.7 2.7m0 5.25h-15m15 0l-2.7-2.7m2.7 2.7l-2.7 2.7",
      countries: "M12 3.75a8.25 8.25 0 100 16.5 8.25 8.25 0 000-16.5zM3.75 12h16.5M12 3.75c2.2 2.1 3.3 5.2 3.3 8.25S14.2 18.15 12 20.25c-2.2-2.1-3.3-5.2-3.3-8.25S9.8 5.85 12 3.75z",
      feature_flags: "M6.75 20.25V4.5m0 1.5h10.5l-2.25 3.75 2.25 3.75H6.75",
      settings: "M12 15a3 3 0 100-6 3 3 0 000 6zM12 3.75l1.5 2.25h2.6l.65 2.6L18.75 12l-2 3.4-.65 2.6h-2.6L12 20.25l-1.5-2.25h-2.6l-.65-2.6-2-3.4.65-2.6h2.6L12 3.75z",
      legal_pages: "M6.75 3.75h7.5l3.75 3.75v12a1.5 1.5 0 01-1.5 1.5h-9.75a1.5 1.5 0 01-1.5-1.5V5.25a1.5 1.5 0 011.5-1.5zM14.25 3.75v3.75h3.75M8.25 12h7.5m-7.5 3.75h5.25",
      newsletter: "M3.75 6.75A1.5 1.5 0 015.25 5.25h13.5a1.5 1.5 0 011.5 1.5v10.5a1.5 1.5 0 01-1.5 1.5h-13.5a1.5 1.5 0 01-1.5-1.5V6.75zM4.5 7l7.5 5.25L19.5 7",
      reports: "M4.5 20.25V4.5m0 1.5h6.375l1.5 2.25-1.5 2.25H4.5m7.875 0H19.5v6.75h-7.125l-1.5-2.25",
      contact_messages: "M4.5 5.25h15a1.5 1.5 0 011.5 1.5v9a1.5 1.5 0 01-1.5 1.5H9.75L6 20.25v-3h-1.5a1.5 1.5 0 01-1.5-1.5v-9a1.5 1.5 0 011.5-1.5zM7.5 9h9m-9 3.75h6",
      audit_logs: "M9 4.5h6a1.1 1.1 0 011.1 1.1v.4h1.4a1.5 1.5 0 011.5 1.5v10.5a1.5 1.5 0 01-1.5 1.5h-11a1.5 1.5 0 01-1.5-1.5V7.5a1.5 1.5 0 011.5-1.5h1.4v-.4A1.1 1.1 0 019 4.5zM9.75 12.75l1.5 1.5 3-3"
    }.freeze

    def admin_nav_icon(key)
      if (simple = SIMPLE_NAV_ICONS[key])
        return '<svg class="h-5 w-5 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.8" ' \
               "stroke=\"currentColor\"><path stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"#{simple}\"/></svg>"
      end

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
