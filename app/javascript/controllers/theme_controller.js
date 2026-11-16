import { Controller } from "@hotwired/stimulus"

// Toggles the `dark` class on <html>. The user's explicit choice is kept in
// localStorage; with no stored choice we respect prefers-color-scheme.
export default class extends Controller {
  static values = {
    storageKey: { type: String, default: "pcmarket.theme" }
  }

  connect() {
    this.applyTheme(this.preferredTheme())
  }

  toggle() {
    const next = document.documentElement.classList.contains("dark") ? "light" : "dark"
    this.storeTheme(next)
    this.applyTheme(next)
  }

  preferredTheme() {
    const stored = this.readStoredTheme()
    if (stored === "dark" || stored === "light") return stored
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"
  }

  applyTheme(theme) {
    document.documentElement.classList.toggle("dark", theme === "dark")
  }

  readStoredTheme() {
    try {
      return localStorage.getItem(this.storageKeyValue)
    } catch {
      // localStorage may be unavailable (private mode, blocked cookies).
      return null
    }
  }

  storeTheme(theme) {
    try {
      localStorage.setItem(this.storageKeyValue, theme)
    } catch {
      // Ignore storage failures; the toggle still works for this page view.
    }
  }
}
