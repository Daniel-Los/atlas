import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["searchCard", "directionsCard"]

  openDirections() {
    this.searchCardTarget.classList.add("hidden")
    this.directionsCardTarget.classList.remove("hidden")
    const input = this.directionsCardTarget.querySelector('[data-routing-target="fromInput"]')
    if (input) input.focus()
  }

  closeDirections() {
    this.directionsCardTarget.classList.add("hidden")
    this.searchCardTarget.classList.remove("hidden")
  }

  stop(event) {
    event.stopPropagation()
  }
}
