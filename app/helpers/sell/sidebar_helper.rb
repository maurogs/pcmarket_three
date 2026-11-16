module Sell
  # Tab styling for sell/_sidebar: active when the request is on the link's
  # path or one of its children (e.g. /sell/sales/:id keeps "My sales" lit).
  module SidebarHelper
    def sell_nav_class(path)
      active = sell_section_active?(path)

      class_names(
        "inline-flex min-h-11 shrink-0 items-center whitespace-nowrap rounded-md px-3 py-2 text-sm font-medium no-underline",
        "bg-primary/10 text-primary" => active,
        "text-muted hover:bg-surface-muted hover:text-text" => !active
      )
    end

    def sell_section_active?(path)
      request.path == path || request.path.start_with?("#{path}/")
    end
  end
end
