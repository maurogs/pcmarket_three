module Admin
  # Bulk option add: a textarea with one value per line. Lines are
  # parameterized into option values (8 GB → 8-gb); duplicates and invalid
  # slugs are skipped and reported.
  class BulkOptionsController < BaseController
    include Auditable

    before_action :set_spec_attribute

    def create
      lines = params.dig(:bulk_option, :values).to_s.split(/[\r\n]+/).map(&:strip).reject(&:empty?)
      position = (@spec_attribute.spec_options.maximum(:position) || 0) + 1

      created = []
      skipped = []
      ActiveRecord::Base.transaction do
        lines.uniq.each do |line|
          value = line.parameterize
          if value.blank? || @spec_attribute.spec_options.exists?(value: value)
            skipped << line
            next
          end

          option = @spec_attribute.spec_options.new(value: value, position: position)
          option.assign_translations(:names, { I18n.default_locale.to_s => line })
          if option.save
            created << option
            position += 1
          else
            skipped << line
          end
        end
      end

      audit!("spec_option_bulk_create", @spec_attribute,
             created: created.map(&:value), skipped: skipped)
      redirect_to edit_admin_spec_attribute_path(@spec_attribute),
                  notice: t(".done", created: created.size, skipped: skipped.size)
    end

    private

    def set_spec_attribute
      @spec_attribute = SpecAttribute.find(params[:spec_attribute_id])
    end
  end
end
