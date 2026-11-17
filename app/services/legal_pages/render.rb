module LegalPages
  # Renders a published LegalPage for the public site (Phase 7b):
  # sanitized markdown → placeholder substitution (values come from the
  # Settings and are HTML-escaped, so a Setting can never inject markup)
  # → anchors + table of contents from the h2 headings.
  class Render
    Result = Struct.new(:body_html, :toc, keyword_init: true)

    PLACEHOLDER = /\{\{(\w+)\}\}/.freeze
    HEADING = %r{<h2>(.+?)</h2>}m.freeze

    include LegalPagesHelper

    def self.call(page)
      new(page).call
    end

    def initialize(page)
      @page = page
    end

    def call
      # to_s on purpose: from here on everything is a plain String, so our
      # one CGI.escapeHTML pass on Setting values is the only escaping that
      # happens (SafeBuffer would double-escape the substitutions).
      body = legal_markdown(@page.body).to_s
      body = substitute_placeholders(body)
      toc = []
      body = body.gsub(HEADING) do
        inner = Regexp.last_match(1)
        id = "sec-#{toc.size + 1}"
        toc << { id: id, label: inner }
        %(<h2 id="#{id}">#{inner}</h2>)
      end
      Result.new(body_html: body.html_safe, toc: toc) # rubocop:disable Rails/OutputSafety
    end

    private

    def substitute_placeholders(html)
      identity = Setting.legal_identity
      html.gsub(PLACEHOLDER) do
        key = Regexp.last_match(1)
        value = identity[key]
        value.nil? ? Regexp.last_match(0) : CGI.escapeHTML(value)
      end
    end
  end
end
