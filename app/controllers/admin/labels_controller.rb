module Admin
  # Catalogue labels CRUD: translated names + badge color; the slug is
  # generated from the name on create (LocalizedSlug).
  class LabelsController < BaseController
    include Auditable

    before_action :set_label, only: %i[edit update destroy]

    def index
      @labels = Label.order(:slug)
    end

    def new
      @label = Label.new
    end

    def create
      @label = Label.new
      assign_attributes(@label)

      if @label.save
        audit!("label_create", @label, slug: @label.slug)
        redirect_to admin_labels_path, notice: t(".created", name: @label.name)
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      assign_attributes(@label)

      if @label.save
        audit!("label_update", @label, slug: @label.slug)
        redirect_to admin_labels_path, notice: t(".updated", name: @label.name)
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @label.destroy!
      audit!("label_destroy", @label, slug: @label.slug)
      redirect_to admin_labels_path, notice: t(".destroyed")
    end

    private

    def set_label
      @label = Label.find(params[:id])
    end

    def assign_attributes(label)
      permitted = params.require(:label).permit(:color, names: {})
      label.assign_attributes(permitted.except(:names))
      label.assign_translations(:names, permitted[:names] || {})
    end
  end
end
