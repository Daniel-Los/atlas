import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  toggle(event) {
    const selected = Array.from(this.element.querySelectorAll('input[type=checkbox]'))
      .filter(cb => cb.checked).map(cb => cb.value)
    const formData = new FormData()
    selected.forEach(name => formData.append("regions[]", name))

    const token = document.querySelector('meta[name="csrf-token"]')?.content
    fetch("/admin/regions", {
      method: "POST",
      body:   formData,
      headers: token ? { "X-CSRF-Token": token, "Accept": "application/json" } : { "Accept": "application/json" }
    })
  }
}
