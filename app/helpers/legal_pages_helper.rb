# Markdown rendering for legal pages: Commonmarker parses the admin-authored
# body, `sanitize` (rails-html-sanitizer) then strips anything outside the
# allowlist — script tags, iframes, event handlers and style attributes
# never reach the page.
module LegalPagesHelper
  ALLOWED_TAGS = %w[p br em strong del ul ol li h1 h2 h3 h4 blockquote
                    code pre a table thead tbody tr th td hr].freeze
  ALLOWED_ATTRIBUTES = %w[href title].freeze

  # Commonmarker 2.x always injects an empty self-anchor (<a href="#…" …
  # class="anchor"></a>) into headings and it survives the sanitizer (a +
  # href are allowed), so strip the empty anchors before sanitizing.
  HEADING_ANCHOR = %r{<a href="[^"]*"[^>]*class="anchor"[^>]*>\s*</a>}.freeze

  def legal_markdown(body)
    html = Commonmarker.to_html(body.to_s).gsub(HEADING_ANCHOR, "")
    sanitize(html, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES)
  end
end
