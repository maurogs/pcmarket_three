module Admin
  # Free-text seller tags CRUD (same shape as labels, no color).
  class SellerTagsController < BaseController
    include Auditable

    before_action :set_seller_tag, only: %i[edit update destroy]

    def index
      @seller_tags = SellerTag.order(:slug)
    end

    def new
      @seller_tag = SellerTag.new
    end

    def create
      @seller_tag = SellerTag.new
      assign_attributes(@seller_tag)

      if @seller_tag.save
        audit!("seller_tag_create", @seller_tag, slug: @seller_tag.slug)
        redirect_to admin_seller_tags_path, notice: t(".created", name: @seller_tag.name)
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      assign_attributes(@seller_tag)

      if @seller_tag.save
        audit!("seller_tag_update", @seller_tag, slug: @seller_tag.slug)
        redirect_to admin_seller_tags_path, notice: t(".updated", name: @seller_tag.name)
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @seller_tag.destroy!
      audit!("seller_tag_destroy", @seller_tag, slug: @seller_tag.slug)
      redirect_to admin_seller_tags_path, notice: t(".destroyed")
    end

    private

    def set_seller_tag
      @seller_tag = SellerTag.find(params[:id])
    end

    def assign_attributes(seller_tag)
      permitted = params.require(:seller_tag).permit(names: {})
      seller_tag.assign_translations(:names, permitted[:names] || {})
    end
  end
end
