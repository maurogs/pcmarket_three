module StoreHelper
  # Store logo URL for a named variant (:thumb, :card); nil when unattached.
  # Unpersisted attachments (a rejected upload mid-form) have no signed_id,
  # so they fall through to the nil/initials placeholder too.
  def store_logo_url(store, variant = :card)
    return unless store&.logo&.attached? && store.logo.persisted?

    store.logo.variant(**Store::LOGO_VARIANTS.fetch(variant.to_sym))
  end

  # Store banner URL for a named variant (:display); nil when unattached.
  def store_banner_url(store, variant = :display)
    return unless store&.banner&.attached? && store.banner.persisted?

    store.banner.variant(**Store::BANNER_VARIANTS.fetch(variant.to_sym))
  end

  # Upper-store name initial, shown where no logo is uploaded.
  def store_initials(store)
    store.name.to_s.strip[0].to_s.upcase
  end
end
