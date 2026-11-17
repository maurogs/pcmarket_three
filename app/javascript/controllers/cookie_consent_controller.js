import { Controller } from "@hotwired/stimulus"

// GDPR cookie consent (Phase 7b). Preferences are stored as URL-encoded
// JSON in a plain `cookie_consent` cookie; ApplicationController parses the
// same shape server-side (see CONSENT_COOKIE). Bumping the server-side
// CONSENT_VERSION invalidates older payloads and re-shows the banner.
export default class extends Controller {
  static targets = ["banner", "dialog", "analytics"]
  static values = { version: { type: Number, default: 1 } }

  static COOKIE_NAME = "cookie_consent"
  static MAX_AGE_SECONDS = 60 * 60 * 24 * 180 // 180 days

  acceptAll(event) {
    event.preventDefault()
    this.#save(["necessary", "analytics"])
  }

  rejectNonEssential(event) {
    event.preventDefault()
    this.#save(["necessary"])
  }

  openPreferences(event) {
    event.preventDefault()
    this.dialogTarget.showModal()
  }

  closePreferences(event) {
    event.preventDefault()
    this.dialogTarget.close()
  }

  savePreferences(event) {
    event.preventDefault()
    const categories = ["necessary"]
    if (this.hasAnalyticsTarget && this.analyticsTarget.checked) categories.push("analytics")
    this.#save(categories)
    this.dialogTarget.close()
  }

  #save(categories) {
    const payload = {
      version: this.versionValue,
      categories,
      timestamp: new Date().toISOString()
    }
    const encoded = encodeURIComponent(JSON.stringify(payload))
    const secure = window.location.protocol === "https:" ? "; Secure" : ""
    document.cookie =
      `${this.constructor.COOKIE_NAME}=${encoded}; path=/; max-age=${this.constructor.MAX_AGE_SECONDS}; SameSite=Lax${secure}`

    this.bannerTarget?.remove()
    this.dispatch("saved", { detail: { categories } })
  }
}
