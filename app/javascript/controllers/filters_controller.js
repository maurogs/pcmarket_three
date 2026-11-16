import { Controller } from "@hotwired/stimulus"

// Filter form on the browse/search results page.
//   * inputs, checkboxes and the sort select auto-submit, debounced by 300 ms
//     so a burst of clicks becomes a single Turbo Frame visit
//   * the same sidebar doubles as a mobile bottom sheet (open/close)
// The form targets the shared `results` Turbo Frame and advances the URL.
export default class extends Controller {
  static targets = ["sheet"]

  connect() {
    this.form = this.element.tagName === "FORM" ? this.element : null
  }

  submit() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.form?.requestSubmit(), 300)
  }

  open(event) {
    event?.preventDefault()
    this.setOpen(true)
  }

  close(event) {
    event?.preventDefault()
    this.setOpen(false)
  }

  setOpen(open) {
    if (!this.hasSheetTarget) return

    this.sheetTarget.classList.toggle("is-open", open)
    this.sheetTarget.setAttribute("aria-hidden", String(!open && this.#isMobile()))

    document.querySelectorAll("[data-filters-toggle]").forEach((button) => {
      button.setAttribute("aria-expanded", String(open))
    })

    document.body.classList.toggle("overflow-hidden", open)
    if (open) this.sheetTarget.focus()
  }

  #isMobile() {
    return window.matchMedia("(max-width: 1023px)").matches
  }
}
