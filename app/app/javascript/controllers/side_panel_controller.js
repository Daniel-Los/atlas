import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["body", "tab", "content", "collapseIcon", "expandIcon"]
  static values  = {
    active:    { type: String, default: "search" },
    expanded:  { type: Boolean, default: true }
  }

  connect() {
    this.render()
  }

  select(event) {
    const tab = event.currentTarget.dataset.tab
    if (this.activeValue === tab && this.expandedValue) {
      // clicking the active tab collapses the panel
      this.expandedValue = false
    } else {
      this.activeValue = tab
      this.expandedValue = true
    }
    this.render()
  }

  toggle() {
    this.expandedValue = !this.expandedValue
    this.render()
  }

  render() {
    this.tabTargets.forEach(btn => {
      const isActive = btn.dataset.tab === this.activeValue && this.expandedValue
      btn.classList.toggle("btn-primary", isActive)
      btn.classList.toggle("text-primary-content", isActive)
      btn.classList.toggle("btn-ghost", !isActive)
    })
    this.bodyTargets.forEach(body => {
      body.classList.toggle("hidden", body.dataset.tab !== this.activeValue)
    })
    if (this.hasContentTarget) {
      this.contentTarget.classList.toggle("hidden", !this.expandedValue)
    }
    if (this.hasCollapseIconTarget && this.hasExpandIconTarget) {
      this.collapseIconTarget.classList.toggle("hidden", !this.expandedValue)
      this.expandIconTarget.classList.toggle("hidden",  this.expandedValue)
    }
  }
}
