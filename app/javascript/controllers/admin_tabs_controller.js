import { Controller } from "@hotwired/stimulus"

// Locale tab strip for the jsonb translation fields in the admin forms:
// each button reveals the panel carrying its data-admin-tabs-key. All six
// inputs stay in the form at once — hidden panels still submit, so editing
// one tab never drops the others.
export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    const initial =
      this.tabTargets.find((tab) => tab.dataset.adminTabsInitial === "true") || this.tabTargets[0]
    if (initial) this.activate(initial.dataset.adminTabsKey)
  }

  show(event) {
    this.activate(event.currentTarget.dataset.adminTabsKey)
  }

  activate(key) {
    this.tabTargets.forEach((tab) => {
      const active = tab.dataset.adminTabsKey === key
      tab.classList.toggle("chip-active", active)
      tab.setAttribute("aria-selected", String(active))
    })
    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.adminTabsKey !== key
    })
  }
}
