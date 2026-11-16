import { Controller } from "@hotwired/stimulus"

// Desktop mega menu: one instance wraps the whole category bar. Buttons and
// panels are paired by index. Opens on hover/focus, toggles on click, closes
// on Escape or when the pointer leaves the bar. The mobile accordion uses
// native <details> elements and needs no JS.
export default class extends Controller {
  static targets = ["button", "panel"]

  connect() {
    this.closeAll()
  }

  show(index) {
    this.buttonTargets.forEach((button, i) => {
      button.setAttribute("aria-expanded", i === index ? "true" : "false")
    })
    this.panelTargets.forEach((panel, i) => panel.classList.toggle("hidden", i !== index))
  }

  open(event) {
    this.show(Number(event.currentTarget.dataset.megaIndex))
  }

  toggle(event) {
    const index = Number(event.currentTarget.dataset.megaIndex)
    if (event.currentTarget.getAttribute("aria-expanded") === "true") {
      this.closeAll()
    } else {
      this.show(index)
    }
  }

  closeAll() {
    this.buttonTargets.forEach((button) => button.setAttribute("aria-expanded", "false"))
    this.panelTargets.forEach((panel) => panel.classList.add("hidden"))
  }

  // Escape closes the panel and returns focus to its button.
  keydown(event) {
    if (event.key !== "Escape") return
    const active = this.panelTargets.find((p) => !p.classList.contains("hidden"))
    if (!active) return
    const index = this.panelTargets.indexOf(active)
    this.closeAll()
    this.buttonTargets[index]?.focus()
  }

  // Close when focus leaves the whole navigation bar.
  focusout(event) {
    if (!this.element.contains(event.relatedTarget)) this.closeAll()
  }
}
