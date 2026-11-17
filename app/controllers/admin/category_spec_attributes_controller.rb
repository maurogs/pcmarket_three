module Admin
  # Attach/detach spec attributes to a category (join-row CRUD through
  # CategorySpecAttribute, incl. the `required` flag and per-category
  # position). Detaching never touches listings or the attribute itself.
  class CategorySpecAttributesController < BaseController
    include Auditable

    before_action :set_category

    def index
      @attachments = @category.category_spec_attributes.includes(:spec_attribute).order(:position, :id)
      @available = SpecAttribute.ordered.where.not(id: @category.spec_attributes.select(:id))
    end

    def create
      row = @category.category_spec_attributes.build(category_spec_attributes_params)

      if row.save
        audit!("category_spec_attribute_attach", row,
               category_slug: @category.slug, spec_key: row.spec_attribute.key)
        redirect_to admin_category_spec_attributes_path(@category), notice: t(".attached")
      else
        redirect_to admin_category_spec_attributes_path(@category), alert: row.errors.full_messages.to_sentence
      end
    end

    def update
      row = @category.category_spec_attributes.find(params[:id])

      if row.update(category_spec_attributes_params)
        audit!("category_spec_attribute_update", row,
               required: row.required, position: row.position)
        redirect_to admin_category_spec_attributes_path(@category), notice: t(".updated")
      else
        redirect_to admin_category_spec_attributes_path(@category), alert: row.errors.full_messages.to_sentence
      end
    end

    def destroy
      row = @category.category_spec_attributes.find(params[:id])
      row.destroy!
      audit!("category_spec_attribute_detach", row,
             category_slug: @category.slug, spec_key: row.spec_attribute.key)
      redirect_to admin_category_spec_attributes_path(@category), notice: t(".detached")
    end

    private

    def set_category
      @category = Category.friendly.find(params[:category_id])
    end

    def category_spec_attributes_params
      params.require(:category_spec_attribute).permit(:spec_attribute_id, :required, :position)
    end
  end
end
