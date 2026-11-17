import { Controller } from "@hotwired/stimulus"

// Collapsible admin sidebar: icon-only rail on small screens, expanded from
// md up until the toggle collapses it again.
export default class extends Controller {
  static targets = ["rail"]

  connect() {
    if (window.matchMedia("(min-width: 40rem)").matches) {
      this.railTarget.classList.add("admin-rail--expanded")
    }
  }

  toggle() {
    this.railTarget.classList.toggle("admin-rail--expanded")
  }
}
