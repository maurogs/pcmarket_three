module Admin
  # Inline option CRUD on the spec attribute edit page. Delete is blocked
  # while listings still use the value — the page offers the merge flow
  # (SpecOptions::Merge) instead.
  class SpecOptionsController < BaseController
    include Auditable

    before_action :set_spec_attribute

    def create
      option = @spec_attribute.spec_options.build(option_params)
      option.assign_translations(:names, option_names)

      if option.save
        audit!("spec_option_create", option, key: @spec_attribute.key, value: option.value)
        redirect_to edit_admin_spec_attribute_path(@spec_attribute), notice: t(".created", value: option.value)
      else
        redirect_to edit_admin_spec_attribute_path(@spec_attribute), alert: option.errors.full_messages.to_sentence
      end
    end

    def update
      option = set_option
      option.assign_translations(:names, option_names)

      if option.update(option_scalar_params)
        audit!("spec_option_update", option, value: option.value, popular: option.popular)
        redirect_to edit_admin_spec_attribute_path(@spec_attribute), notice: t(".updated", value: option.value)
      else
        redirect_to edit_admin_spec_attribute_path(@spec_attribute), alert: option.errors.full_messages.to_sentence
      end
    end

    def destroy
      option = set_option
      in_use = option.listings_using_count

      if in_use.positive?
        audit!("spec_option_delete_blocked", option, value: option.value, listings_in_use: in_use)
        redirect_to edit_admin_spec_attribute_path(@spec_attribute),
                    alert: t(".in_use", count: in_use, value: option.value)
      else
        option.destroy!
        audit!("spec_option_destroy", option, key: @spec_attribute.key, value: option.value)
        redirect_to edit_admin_spec_attribute_path(@spec_attribute), notice: t(".destroyed", value: option.value)
      end
    end

    private

    def set_spec_attribute
      @spec_attribute = SpecAttribute.find(params[:spec_attribute_id])
    end

    def set_option
      @spec_attribute.spec_options.find(params[:id])
    end

    def option_params
      params.require(:spec_option).permit(:value, :popular, :position)
    end

    def option_scalar_params
      params.require(:spec_option).permit(:popular, :position)
    end

    def option_names
      params.require(:spec_option).permit(names: {})[:names] || {}
    end
  end
end
