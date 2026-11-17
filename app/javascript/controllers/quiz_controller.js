import { Controller } from "@hotwired/stimulus"

// Multi-step PC Finder quiz (progressive enhancement): without JS the whole
// form stays visible; with JS each step is a panel with dots + next/back,
// and selecting a game caps choices at the server-side MAX_GAMES (3).
export default class extends Controller {
  static targets = ["step", "dot", "game"]
  static values = { maxGames: { type: Number, default: 3 } }

  connect() {
    this.current = 0
    this.showStep(0)
  }

  next() {
    this.showStep(Math.min(this.current + 1, this.stepTargets.length - 1))
  }

  back() {
    this.showStep(Math.max(this.current - 1, 0))
  }

  goTo(event) {
    this.showStep(Number(event.params.index))
  }

  // Keep the first N game checkboxes enabled; the rest lock once full.
  toggleGame(event) {
    const checked = this.gameTargets.filter((box) => box.checked)
    if (checked.length >= this.maxGamesValue) {
      this.gameTargets.forEach((box) => { box.disabled = !box.checked })
    } else {
      this.gameTargets.forEach((box) => { box.disabled = false })
    }
  }

  showStep(index) {
    this.current = index
    this.stepTargets.forEach((step, i) => {
      step.hidden = i !== index
    })
    this.dotTargets.forEach((dot, i) => {
      dot.setAttribute("aria-current", i === index ? "step" : "false")
      dot.classList.toggle("bg-primary", i === index)
      dot.classList.toggle("bg-border", i !== index)
    })
    this.stepTargets[index]?.scrollIntoView({ block: "nearest", behavior: "smooth" })
  }
}
