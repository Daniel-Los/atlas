import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }

  open() {
    const intents = this.collectIntents()
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const headers = { "Accept": "text/vnd.turbo-stream.html", "Content-Type": "application/json" }
    if (token) headers["X-CSRF-Token"] = token

    fetch(this.urlValue, {
      method: "POST",
      headers,
      body: JSON.stringify({ service_intents: intents })
    }).then(r => r.text()).then(html => {
      const slot = document.querySelector("#apply_confirmation")
      if (slot) slot.innerHTML = html
    })
  }

  close() {
    const slot = document.querySelector("#apply_confirmation")
    if (slot) slot.innerHTML = ""
  }

  collectIntents() {
    return Array.from(document.querySelectorAll("[data-controller~='service-toggle']"))
      .map(el => {
        const input  = el.querySelector("input[type=checkbox]")
        if (!input) return null
        const name    = el.dataset.serviceToggleNameValue
        const current = el.dataset.serviceToggleCurrentValue === "true"
        const wanted  = input.checked
        return wanted === current ? null : { name, enabled: wanted }
      })
      .filter(Boolean)
  }
}
