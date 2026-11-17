# Labels and seller tags get a slug from their English (or first) name when
# the admin form doesn't supply one.
module LocalizedSlug
  extend ActiveSupport::Concern

  included do
    before_validation :ensure_localized_slug, on: :create
  end

  private

  def ensure_localized_slug
    return if slug.present?

    names_hash = names.to_h
    base = names_hash["en"].presence || names_hash.values.map(&:presence).compact.first
    candidate = base.to_s.parameterize.presence || self.class.name.demodulize.underscore.dasherize
    candidate = "#{candidate}-#{id || SecureRandom.hex(3)}" if self.class.exists?(slug: candidate)
    self.slug = candidate
  end
end
