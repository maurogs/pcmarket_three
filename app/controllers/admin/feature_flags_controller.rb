module Admin
  # Feature flags console (Phase 6b): the five known flags (registry in
  # config/initializers/flipper.rb) with on/off + percentage-of-actors
  # rollout. Enabling without the prerequisite env/config only shows a
  # warning; every write is audited.
  class FeatureFlagsController < BaseController
    include Auditable

    def index
      # Lazy safety net: registers any feature not in the adapter yet
      # (default OFF) so the page never renders/queries unknown flags.
      FeatureFlags.register_all!

      @flags = FeatureFlags::FEATURES.map do |key, meta|
        feature = Flipper[key]
        {
          key: key,
          description_key: meta.fetch(:description_key),
          enabled: feature.enabled?,
          percentage: feature.percentage_of_actors_value.to_i,
          state: feature.state.to_s,
          warning: FeatureFlags.warning_for(key, enabled: feature.enabled?)
        }
      end
    end

    def update
      key = params[:id].to_s
      return head(:not_found) unless FeatureFlags::FEATURES.key?(key)

      outcome = apply(key)
      audit!("feature_flag_update", nil, key: key, outcome: outcome)
      redirect_to admin_feature_flags_path, notice: t(".updated", key: key, outcome: outcome)
    end

    private

    def apply(key)
      case params[:switch]
      when "on"
        Flipper.enable(key)
        "on"
      when "percentage"
        percentage = params[:percentage].to_i.clamp(1, 99)
        Flipper.enable_percentage_of_actors(key, percentage)
        "percentage:#{percentage}"
      else
        Flipper.disable(key)
        "off"
      end
    end
  end
end
