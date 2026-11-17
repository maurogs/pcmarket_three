module Admin
  # Category tree admin: tree index with up/down ordering, create/edit with
  # translated names & SEO descriptions, archive via the active flag.
  # Ordering posts to the nested :position resource (see PositionsController).
  class CategoriesController < BaseController
    include Auditable

    before_action :set_category, only: %i[edit update]

    def index
      @categories = Category.roots.ordered.includes(:children)
    end

    def new
      @category = Category.new
    end

    def create
      @category = Category.new
      assign_attributes(@category)

      if @category.save
        audit!("category_create", @category, slug: @category.slug, parent_id: @category.parent_id)
        redirect_to admin_categories_path, notice: t(".created", name: @category.name)
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      assign_attributes(@category)

      if @category.save
        audit!("category_update", @category,
               slug: @category.slug, active: @category.active,
               parent_id: @category.parent_id)
        redirect_to admin_categories_path, notice: t(".updated", name: @category.name)
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_category
      @category = Category.friendly.find(params[:id])
    end

    def assign_attributes(category)
      permitted = params.require(:category).permit(:parent_id, :icon, :active,
                                                   names: {}, seo_descriptions: {})
      # names/seo_descriptions are merged per-locale by the concern, never
      # assigned wholesale (untouched tabs must survive).
      category.assign_attributes(permitted.except(:names, :seo_descriptions))
      category.assign_translations(:names, permitted[:names] || {})
      category.assign_translations(:seo_descriptions, permitted[:seo_descriptions] || {})
    end
  end
end
