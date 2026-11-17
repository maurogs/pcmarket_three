import { Controller } from "@hotwired/stimulus"

// Client-side filter for the help-centre FAQ (/pages/help). Each <details>
// carries a data-keywords attribute (question + answer); a match on the
// search term opens it, a non-match hides it, and whole groups hide when
// all of their questions fall out.
export default class extends Controller {
  static targets = ["input", "item", "section", "empty"]

  filter() {
    const term = this.inputTarget.value.trim().toLowerCase()

    this.itemTargets.forEach((item) => {
      const haystack = (item.dataset.keywords || "").toLowerCase()
      const match = term === "" || haystack.includes(term)
      item.hidden = !match
      if (term !== "" && match) item.open = true
      if (term === "") item.open = false
    })

    this.sectionTargets.forEach((section) => {
      const anyVisible = section
        .querySelectorAll("details[data-faq-filter-target='item']")
        .length > 0 && [...section.querySelectorAll("details")].some((d) => !d.hidden)
      section.hidden = !anyVisible
    })

    if (this.hasEmptyTarget) {
      const anyVisible = this.itemTargets.some((item) => !item.hidden)
      this.emptyTarget.hidden = anyVisible
    }
  }
}
