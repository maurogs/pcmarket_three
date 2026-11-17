module Admin
  # "Merge into another option" (nested singular resource on the option
  # row): POST rewrites every listing's specs with SpecOptions::Merge and
  # removes the source option — the escape hatch for options that are in
  # use and therefore blocked from plain deletion.
  class SpecOptionMergesController < BaseController
    include Auditable

    def create
      spec_attribute = SpecAttribute.find(params[:spec_attribute_id])
      option = spec_attribute.spec_options.find(params[:spec_option_id])
      target = spec_attribute.spec_options.find_by(id: params.dig(:merge, :target_id))

      if target.nil? || target.id == option.id
        redirect_to edit_admin_spec_attribute_path(spec_attribute), alert: t(".invalid_target")
        return
      end

      result = SpecOptions::Merge.call(option: option, target: target)
      audit!("spec_option_merge", target,
             source_value: option.value, target_value: target.value,
             listings_rewritten: result.listings_rewritten)
      redirect_to edit_admin_spec_attribute_path(spec_attribute),
                  notice: t(".merged", source: option.value, target: target.value,
                                   count: result.listings_rewritten)
    rescue ArgumentError => e
      redirect_to edit_admin_spec_attribute_path(spec_attribute), alert: e.message
    end
  end
end
