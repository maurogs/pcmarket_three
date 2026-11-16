import { Controller } from "@hotwired/stimulus"

// Chat thread chrome: Turbo appends identical markup to every viewer, so
// bubbles carry data-sender-id and this controller aligns "mine on the
// right / theirs on the left" per viewer. It re-aligns whenever Turbo
// appends new rows (the container itself is never replaced, so Stimulus
// does not reconnect) and keeps the newest message in view.
export default class extends Controller {
  connect() {
    this.align()
    this.scrollToLatest()
    this.observer = new MutationObserver(() => this.align())
    this.observer.observe(this.element, { childList: true })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  align() {
    const me = this.data.get("currentUser")
    if (!me) return
    this.element.querySelectorAll("[data-message]").forEach((row) => {
      const mine = row.dataset.senderId === me
      row.classList.toggle("justify-end", mine)
      const bubble = row.querySelector("[data-bubble]")
      if (!bubble) return
      bubble.classList.toggle("bg-primary", mine)
      bubble.classList.toggle("text-white", mine)
    })
  }

  scrollToLatest() {
    const rows = this.element.querySelectorAll("[data-message]")
    rows[rows.length - 1]?.scrollIntoView({ block: "end" })
  }
}
