# Legal-text seeds (Phase 7c). Documents are plain Markdown under
# db/seeds/legal/<COUNTRY>/<locale>/<slug>.md — the first line `# Title`
# becomes the title, the rest is the body. Upserts by
# (country_code, locale, slug) with published: true and
# needs_legal_review: true, because a seeded text is a TEMPLATE: it must be
# reviewed by counsel before it is legally relied on.
#
# Guard (the point of needs_legal_review): a page whose needs_legal_review is
# false has been edited/approved by an admin from the template — the loader
# NEVER overwrites it, it only logs a skip. Idempotent: re-running with no
# admin edits updates titles/bodies in place and creates nothing new.
legal_root = Rails.root.join("db", "seeds", "legal")
available_locales = I18n.available_locales.map(&:to_s)

Dir.glob(legal_root.join("**", "*.md")).sort.each do |path|
  rel = Pathname.new(path).relative_path_from(legal_root)
  parts = rel.each_filename.to_a
  country_code, locale, filename = parts
  slug = File.basename(filename, ".md")

  unless parts.size == 3 &&
         country_code.to_s.match?(/\A[A-Z]{2}\z/) &&
         available_locales.include?(locale) &&
         LegalPage::SLUGS.include?(slug)
    Rails.logger.warn "legal seed: ignoring #{rel} " \
                      "(expected <COUNTRY>/<locale>/<slug>.md, slug in #{LegalPage::SLUGS.join(", ")})"
    next
  end

  page = LegalPage.find_or_initialize_by(country_code: country_code, locale: locale, slug: slug)
  if page.persisted? && !page.needs_legal_review?
    Rails.logger.info "legal seed: skipping #{rel} — approved by legal counsel, " \
                      "the admin text wins over the template"
    next
  end

  lines = File.read(path).lines
  title = lines.first.to_s.strip[/\A#\s+(.+?)\s*\z/, 1]
  raise ArgumentError, "legal seed #{rel} must start with '# Title' on the first line" if title.blank?

  page.assign_attributes(title: title, body: lines.drop(1).join.lstrip,
                         published: true, needs_legal_review: true)
  page.save!
end
