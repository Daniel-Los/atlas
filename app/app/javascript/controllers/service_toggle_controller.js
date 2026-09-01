import { Controller } from "@hotwired/stimulus"

// Page-level map of staged intents: service name → desired enabled boolean.
// Survives Turbo-stream re-renders of the service card; the new controller
// reads from STAGED on connect and re-applies the user's intent.
//
// Cleared automatically when the staged state matches the persisted state
// (apply completed) or when the user toggles back to the original value.
const STAGED = new Map()

export default class extends Controller {
  static values  = { name: String, current: Boolean }
  static targets = ["input", "badge"]

  connect() {
    if (!STAGED.has(this.nameValue)) return
    const wanted = STAGED.get(this.nameValue)
    this.inputTarget.checked = wanted
    if (wanted === this.currentValue) {
      STAGED.delete(this.nameValue)
      this.clearPending()
    } else {
      this.markPending(wanted)
    }
  }

  flip() {
    const wanted = this.inputTarget.checked
    if (wanted === this.currentValue) {
      STAGED.delete(this.nameValue)
      this.clearPending()
    } else {
      STAGED.set(this.nameValue, wanted)
      this.markPending(wanted)
    }
  }

  markPending(wanted) {
    this.card().classList.add("ring-1", "ring-warning")
    if (this.hasBadgeTarget) {
      this.badgeTarget.hidden = false
      this.badgeTarget.textContent = wanted ? "will enable" : "will disable"
    }
  }

  clearPending() {
    this.card().classList.remove("ring-1", "ring-warning")
    if (this.hasBadgeTarget) this.badgeTarget.hidden = true
  }

  card() {
    return this.element.closest("[id^='service_']") || this.element
  }
}
