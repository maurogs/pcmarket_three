import { Controller } from "@hotwired/stimulus"

// Keyboard shortcuts for the moderation queue page:
//   a → approve (submits the inline approve form)
//   r → open the reject form
//   j / k → previous / next pending listing
// Ignores keystrokes while typing or with modifiers held.
export default class extends Controller {
  static targets = ["approveForm", "rejectLink"]
  static values = { prevUrl: String, nextUrl: String }

  connect() {
    this.keyHandler = (event) => this.handleKey(event)
    window.addEventListener("keydown", this.keyHandler)
  }

  disconnect() {
    window.removeEventListener("keydown", this.keyHandler)
  }

  handleKey(event) {
    if (event.metaKey || event.ctrlKey || event.altKey) return
    if (/^(input|textarea|select)$/i.test(event.target.tagName)) return

    switch (event.key) {
      case "a":
        event.preventDefault()
        this.approveFormTarget.requestSubmit()
        break
      case "r":
        event.preventDefault()
        this.rejectLinkTarget.click()
        break
      case "j":
        this.goto(this.prevUrlValue)
        break
      case "k":
        this.goto(this.nextUrlValue)
        break
    }
  }

  goto(url) {
    if (url) window.location.assign(url)
  }
}
