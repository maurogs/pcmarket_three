import { Controller } from "@hotwired/stimulus"

// Chat composer: Enter sends, Shift+Enter inserts a newline, and a live
// counter mirrors the server-side maximum (2000 chars). The textarea itself
// carries maxlength so the counter is informational only.
export default class extends Controller {
  static targets = ["input", "counter"]
  static values = { max: { type: Number, default: 2000 } }

  connect() {
    this.refresh()
  }

  keydown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      const input = this.inputTarget
      if (!input.disabled && input.value.trim().length > 0) {
        input.closest("form").requestSubmit()
      }
    }
  }

  refresh() {
    if (!this.hasCounterTarget) return
    const left = this.maxValue - this.inputTarget.value.length
    this.counterTarget.textContent = left
    this.counterTarget.classList.toggle("text-rose-600", left < 100)
  }
}
