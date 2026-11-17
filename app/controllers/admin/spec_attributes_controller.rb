module Admin
  # "Filters" admin: spec attributes (key frozen after create — the key is
  # what listing specs jsonb and saved-search filters reference) with
  # inline option management (see SpecOptionsController and the bulk
  # add on the edit page).
  class SpecAttributesController < BaseController
    include Auditable

    before_action :set_spec_attribute, only: %i[edit update destroy]

    def index
      @spec_attributes = SpecAttribute.ordered.includes(:spec_options)
    end

    def new
      @spec_attribute = SpecAttribute.new(input_type: :select)
      @spec_options = []
    end

    def create
      @spec_attribute = SpecAttribute.new
      assign_attributes(@spec_attribute)

      if @spec_attribute.save
        audit!("spec_attribute_create", @spec_attribute, key: @spec_attribute.key)
        redirect_to edit_admin_spec_attribute_path(@spec_attribute), notice: t(".created", key: @spec_attribute.key)
      else
        @spec_options = @spec_attribute.spec_options.to_a
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @spec_options = @spec_attribute.spec_options.includes(:spec_attribute).to_a
    end

    def update
      assign_attributes(@spec_attribute)

      if @spec_attribute.save
        audit!("spec_attribute_update", @spec_attribute,
               key: @spec_attribute.key, filterable: @spec_attribute.filterable)
        redirect_to edit_admin_spec_attribute_path(@spec_attribute), notice: t(".updated", key: @spec_attribute.key)
      else
        @spec_options = @spec_attribute.spec_options.to_a
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      # Mirrors SpecOptionsController: while any option is still referenced by
      # listings, deleting the attribute would silently strip those spec values.
      in_use = @spec_attribute.spec_options.sum(&:listings_using_count)

      if in_use.positive?
        audit!("spec_attribute_delete_blocked", @spec_attribute,
               key: @spec_attribute.key, listings_in_use: in_use)
        redirect_to admin_spec_attributes_path,
                    alert: t("admin.spec_options.destroy.in_use", count: in_use, value: @spec_attribute.key)
        return
      end

      @spec_attribute.destroy!
      audit!("spec_attribute_destroy", @spec_attribute, key: @spec_attribute.key)
      redirect_to admin_spec_attributes_path, notice: t(".destroyed", key: @spec_attribute.key)
    end

    private

    def set_spec_attribute
      @spec_attribute = SpecAttribute.find(params[:id])
    end

    def assign_attributes(spec_attribute)
      permitted = params.require(:spec_attribute).permit(:input_type, :unit, :group, :filterable, :position, names: {})
      # `key` is accepted on create only; on update it is filtered out so the
      # frozen key can never change (the model has the same guard).
      if spec_attribute.new_record?
        spec_attribute.assign_attributes(permitted.except(:names).merge(key: params.dig(:spec_attribute, :key)))
      else
        spec_attribute.assign_attributes(permitted.except(:names))
      end
      spec_attribute.assign_translations(:names, permitted[:names] || {})
    end
  end
end
