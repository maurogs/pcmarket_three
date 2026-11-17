module Admin
  # Grouped site-settings form (singular resource). Values are read back
  # through Setting.get; writes go through Admin::Settings::Update, which
  # validates types/ranges before touching any key. Audited as one row.
  class SettingsController < BaseController
    include Auditable

    def edit
      @values = current_values
      @errors = {}
    end

    def update
      result = Admin::Settings::Update.call(form_params)

      if result.errors.any?
        @errors = result.errors
        @values = form_params.to_h.deep_stringify_keys # show what was typed
        flash.now[:alert] = t(".invalid")
        render :edit, status: :unprocessable_entity
      else
        audit!("settings_update", nil, keys: changed_keys_preview)
        redirect_to edit_admin_settings_path, notice: t(".updated")
      end
    end

    private

    def form_params
      params.require(:settings).permit(
        :site_name, :support_email, :support_phone, :commission_percent,
        :featured_price_cents, :featured_days, :min_offer_percent,
        :announcement_enabled, :maintenance_mode,
        announcement_text: I18n.available_locales.map(&:to_s),
        social_links: Admin::Settings::SOCIAL_SITES,
        default_meta_description: I18n.available_locales.map(&:to_s)
      )
    end

    def current_values
      announcement = Setting.get("announcement", {}) || {}
      {
        "site_name" => Setting.get("site_name", ""),
        "support_email" => Setting.get("support_email", ""),
        "support_phone" => Setting.get("support_phone", ""),
        "commission_percent" => format("%.2f", Setting.get("commission_percent", 0).to_f),
        "featured_price_cents" => format("%.2f", Setting.get("featured_price_cents", 0).to_i / 100.0),
        "featured_days" => Setting.get("featured_days", 7),
        "min_offer_percent" => Setting.get("min_offer_percent", 50),
        "announcement_enabled" => announcement["enabled"] == true,
        "announcement_text" => announcement["text"] || {},
        "maintenance_mode" => Setting.get("maintenance_mode", false) == true,
        "social_links" => Setting.get("social_links", {}) || {},
        "default_meta_description" => Setting.get("default_meta_description", {}) || {}
      }
    end

    def changed_keys_preview
      %w[site_name support_email support_phone commission_percent featured_price_cents
         featured_days min_offer_percent announcement maintenance_mode social_links
         default_meta_description]
    end
  end
end
