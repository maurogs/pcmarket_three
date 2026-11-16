import { Controller } from "@hotwired/stimulus"

// Listing gallery: arrows, thumbnails, keyboard arrows and touch swipe.
// Slides are server-rendered; the controller only toggles which one is visible.
export default class extends Controller {
  static targets = ["slide", "thumb", "counter"]
  static values = { index: { type: Number, default: 0 } }

  connect() {
    this.count = this.slideTargets.length
    this.show(this.indexValue)
  }

  select(event) {
    this.show(Number(event.params.index))
  }

  next() {
    this.show((this.indexValue + 1) % this.count)
  }

  previous() {
    this.show((this.indexValue - 1 + this.count) % this.count)
  }

  keydown(event) {
    if (event.key === "ArrowRight") {
      event.preventDefault()
      this.next()
    } else if (event.key === "ArrowLeft") {
      event.preventDefault()
      this.previous()
    }
  }

  // Touch swipe, bound by the template on the stage element.
  pointerdown(event) {
    this.startX = event.clientX
  }

  pointerup(event) {
    if (this.startX === undefined) return

    const delta = event.clientX - this.startX
    this.startX = undefined
    if (Math.abs(delta) < 40) return

    delta < 0 ? this.next() : this.previous()
  }

  show(index) {
    if (this.count === 0) return

    index = ((index % this.count) + this.count) % this.count
    this.indexValue = index

    this.slideTargets.forEach((slide, i) => slide.classList.toggle("hidden", i !== index))
    this.thumbTargets.forEach((thumb, i) => {
      thumb.classList.toggle("ring-2", i === index)
      thumb.classList.toggle("ring-primary", i === index)
      thumb.setAttribute("aria-current", i === index ? "true" : "false")
    })

    if (this.hasCounterTarget) this.counterTarget.textContent = `${index + 1} / ${this.count}`
  }
}
