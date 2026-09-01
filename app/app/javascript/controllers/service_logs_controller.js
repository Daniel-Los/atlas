import { Controller } from "@hotwired/stimulus"

// One per service card. Lazily fetches `last N` log lines and optionally
// auto-refreshes while the panel is open.
export default class extends Controller {
  static targets = ["panel", "output", "autoRefresh"]
  static values  = { name: String, url: String, intervalMs: { type: Number, default: 3000 } }

  disconnect() {
    this.stopAutoRefresh()
  }

  toggle() {
    if (this.panelTarget.classList.contains("hidden")) {
      this.panelTarget.classList.remove("hidden")
      this.fetchLogs()
    } else {
      this.panelTarget.classList.add("hidden")
      this.stopAutoRefresh()
    }
  }

  refresh() {
    this.fetchLogs()
  }

  toggleAutoRefresh() {
    if (this.autoRefreshTarget.checked) {
      this.startAutoRefresh()
    } else {
      this.stopAutoRefresh()
    }
  }

  startAutoRefresh() {
    this.stopAutoRefresh()
    this.timer = setInterval(() => this.fetchLogs(), this.intervalMsValue)
  }

  stopAutoRefresh() {
    if (this.timer) { clearInterval(this.timer); this.timer = null }
  }

  async fetchLogs() {
    try {
      const url = new URL(this.urlValue, window.location.origin)
      url.searchParams.set("tail", "200")
      const res = await fetch(url.toString(), { headers: { Accept: "text/plain" } })
      const txt = await res.text()
      if (!res.ok) {
        this.outputTarget.textContent = `(${res.status}) ${txt}`
        return
      }
      this.outputTarget.textContent = stripAnsi(txt)
      // Scroll to bottom — log tail UX.
      this.outputTarget.scrollTop = this.outputTarget.scrollHeight
    } catch (err) {
      this.outputTarget.textContent = `Network error: ${err.message}`
    }
  }
}

// Strip ANSI colour escapes (docker compose logs include them even with
// --no-color when the upstream emits them directly).
function stripAnsi(s) {
  // eslint-disable-next-line no-control-regex
  return String(s).replace(/\x1b\[[0-9;]*m/g, "")
}
