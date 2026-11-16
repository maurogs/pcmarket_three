import { Controller } from "@hotwired/stimulus"

// Hamburger button + slide-in menu for < md screens.
export default class extends Controller {
  static targets = ["button", "panel", "backdrop"]

  connect() {
    this.close()
  }

  toggle(event) {
    event.preventDefault()
    if (this.isOpen()) {
      this.close()
    } else {
      this.open()
    }
  }

  open() {
    this.panelTarget.classList.remove("-translate-x-full")
    this.backdropTarget.classList.remove("hidden")
    this.setExpanded(true)
  }

  close() {
    this.panelTarget.classList.add("-translate-x-full")
    this.backdropTarget.classList.add("hidden")
    this.setExpanded(false)
  }

  isOpen() {
    return !this.panelTarget.classList.contains("-translate-x-full")
  }

  setExpanded(expanded) {
    this.buttonTargets.forEach((button) => button.setAttribute("aria-expanded", String(expanded)))
  }
}
