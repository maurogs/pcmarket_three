module ApplicationHelper
  # Inline SVG icons (Heroicons outline, MIT) so we ship no icon font.
  # Add new icons here as the marketplace UI grows.
  ICON_PATHS = {
    chip: '<path d="M8.25 3v1.5M4.5 8.25H3m18 0h-1.5M4.5 12H3m18 0h-1.5m-15 3.75H3m18 0h-1.5M8.25 19.5V21M12 3v1.5m0 15V21m3.75-18v1.5m0 15V21m-9-1.5h10.5a2.25 2.25 0 0 0 2.25-2.25V6.75a2.25 2.25 0 0 0-2.25-2.25H6.75A2.25 2.25 0 0 0 4.5 6.75v10.5a2.25 2.25 0 0 0 2.25 2.25Z"/>',
    heart: '<path d="M21 8.25c0-2.485-2.099-4.5-4.685-4.5C14.24 3.75 12 6 12 6s-2.24-2.25-4.315-2.25C5.1 3.75 3 5.765 3 8.25c0 7.22 9 12 9 12s9-4.78 9-12Z"/>',
    bell: '<path d="M14.857 17.082a23.848 23.848 0 0 0 5.454-1.31A8.967 8.967 0 0 1 18 9.75V9A6 6 0 0 0 6 9v.75a8.967 8.967 0 0 1-2.313 6.022c1.733.64 3.56 1.085 5.455 1.31m5.714 0a24.255 24.255 0 0 1-5.714 0m5.714 0a3 3 0 1 1-5.714 0"/>',
    cart: '<path d="M2.25 3h1.386c.51 0 .955.343 1.087.836l.383 1.437M7.5 14.25a3 3 0 0 0-3 3h15.75m-12.75-3h11.218c1.121-2.3 2.1-4.684 2.924-7.138a60.114 60.114 0 0 0-16.536-1.84M7.5 14.25 5.106 5.272M6 20.25a.75.75 0 1 1-1.5 0 .75.75 0 0 1 1.5 0Zm12.75 0a.75.75 0 1 1-1.5 0 .75.75 0 0 1 1.5 0Z"/>',
    user: '<path d="M17.982 18.725A7.488 7.488 0 0 0 12 15.75a7.488 7.488 0 0 0-5.982 2.975m11.963 0a9 9 0 1 0-11.963 0m11.963 0A8.966 8.966 0 0 1 12 21a8.966 8.966 0 0 1-5.982-2.275M15 9.75a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z"/>',
    # Category icons (simple original glyphs; names match categories.icon)
    gamepad: '<path d="M7 8h10a4.5 4.5 0 0 1 4.4 3.6l.9 4.3A2.6 2.6 0 0 1 19.7 19c-1 0-1.9-.6-2.4-1.5L16.4 16H7.6l-.9 1.5A2.6 2.6 0 0 1 4.3 19a2.6 2.6 0 0 1-2.6-3.1l.9-4.3A4.5 4.5 0 0 1 7 8Zm-1 3.5h2M7.5 10v3"/><circle cx="16.2" cy="11.2" r=".1"/><circle cx="17.8" cy="12.8" r=".1"/>',
    gpu: '<path d="M3 6h18v10H5a2 2 0 0 1-2-2V6Zm2 10v2m14-2v2"/><circle cx="9" cy="11" r="2.5"/><path d="M15 9v4h4V9h-4Z"/>',
    cpu: '<path d="M7 7h10v10H7V7Zm3-3v2m4-2v2M7 3v2m10-2v2M7 19v2m3-2v2m4-2v2m3-2v2M3 7h2m-2 4h2m-2 4h2m14-8h2m-2 4h2m-2 4h2"/>',
    monitor: '<path d="M3 5h18v11H3V5Zm4 14h10m-7-3v3m4-3v3"/>',
    laptop: '<path d="M5 6h14a1 1 0 0 1 1 1v9H4V7a1 1 0 0 1 1-1Zm-2 12h18"/>',
    smartphone: '<path d="M8 3h8a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H8a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1Zm2 15h4"/>',
    desktop: '<path d="M6 3h12a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1Zm2 3h8M8 9h8m-6 8h4"/>',
    keyboard: '<path d="M3 7h18v10H3V7Zm3 3h.01M9 10h.01m3 0h.01M15 10h.01m3 0h.01M6 13h.01m12 0h.01M8 13h8"/>',
    disc: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="2.5"/>',
    # Utility icons
    shield: '<path d="M12 3 5 6v5c0 4.4 3 8.3 7 10 4-1.7 7-5.6 7-10V6l-7-3Zm-3 8.5 2.2 2.5L15 9"/>',
    lock: '<path d="M7 11V8a5 5 0 0 1 10 0v3M5 11h14a1 1 0 0 1 1 1v7a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1v-7a1 1 0 0 1 1-1Zm7 4v2"/>',
    tag: '<path d="M3 3h7l11 11-7 7L3 10V3Zm4 4h.01"/>',
    filter: '<path d="M4 6h16M7 12h10m-7 6h4"/>',
    chevron_down: '<path d="m6 9 6 6 6-6"/>',
    chevron_left: '<path d="m14 6-6 6 6 6"/>',
    chevron_right: '<path d="m10 6 6 6-6 6"/>',
    map_pin: '<path d="M12 21s7-6.1 7-11a7 7 0 1 0-14 0c0 4.9 7 11 7 11Zm0-8.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5Z"/>',
    check: '<path d="m5 13 4 4L19 7"/>',
    close: '<path d="m6 6 12 12M18 6 6 18"/>',
    search: '<circle cx="11" cy="11" r="7"/><path d="m16.5 16.5 4 4"/>',
    truck: '<path d="M3 7h11v9H3V7Zm11 3h4l3 3v3h-7M7 19a2 2 0 1 0 0-4 2 2 0 0 0 0 4Zm11 0a2 2 0 1 0 0-4 2 2 0 0 0 0 4Z"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3.5 2"/>',
    message: '<path d="M4 5h16a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H9l-5 4V6a1 1 0 0 1 1-1Z"/>',
    returns: '<path d="M9 10 5 6l4-4M5 6h9a5 5 0 0 1 0 10H8"/>',
    box: '<path d="M3 8h18v12H3V8Zm0 0 3-4h12l3 4M9 12h6"/>',
    bolt: '<path d="M13 3 5 13h6l-1 8 9-11h-6l1-7Z"/>',
    eye: '<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12Z"/><circle cx="12" cy="12" r="2.8"/>',
    image: '<rect x="3" y="5" width="18" height="14" rx="1.5"/><circle cx="9" cy="10" r="1.6"/><path d="m5 17 4.5-4.5L12 15l3-3 4 4"/>',
    plus: '<path d="M12 5v14M5 12h14"/>'
  }.freeze

  # Category glyph, matched against ICON_PATHS by categories.icon; nil when the
  # category has no known icon so the view can pick a fallback.
  def category_icon(category, classes: "size-7")
    name = category.icon.presence
    return unless name && ICON_PATHS.key?(name)

    inline_icon(name, classes: classes)
  end

  def inline_icon(name, classes: "size-5")
    svg = tag.svg(
      raw(ICON_PATHS.fetch(name)),
      class: "#{classes} shrink-0",
      viewBox: "0 0 24 24",
      fill: "none",
      stroke: "currentColor",
      "stroke-width": 1.8,
      "stroke-linecap": "round",
      "stroke-linejoin": "round",
      "aria-hidden": true
    )
    svg
  end
end
