import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import MapHook from "./hooks/map"
import LogStreamHook from "./hooks/log_stream"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {Map: MapHook, LogStream: LogStreamHook}
})

topbar.config({barColors: {0: "#3b82f6"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

liveSocket.connect()
window.liveSocket = liveSocket

window.atlasToggleTheme = () => {
  const root = document.documentElement
  const current = root.getAttribute("data-theme")
  root.setAttribute(
    "data-theme",
    current === "bunker-brutalist" ? "forest-patina" : "bunker-brutalist"
  )
}

function setupMobileSheetDrag() {
  if (window.innerWidth > 639) return

  const sheet = document.querySelector(".atlas-side-panel-content")
  const panel = document.querySelector(".atlas-side-panel")
  if (!sheet || !panel || sheet.dataset.dragBound === "true") return

  let startY = 0
  let startHeight = 0
  let dragging = false

  const setHeight = (value) => {
    const minH = 180
    const maxH = Math.min(window.innerHeight * 0.62, 420)
    const next = Math.min(Math.max(value, minH), maxH)
    sheet.style.height = `${next}px`
  }

  sheet.addEventListener("pointerdown", (event) => {
    if (window.innerWidth > 639) return
    if (event.target.closest("button, input, textarea, select, a, label")) return

    dragging = true
    startY = event.clientY
    startHeight = sheet.offsetHeight
    sheet.setPointerCapture?.(event.pointerId)
    panel.classList.add("atlas-dragging")
  })

  sheet.addEventListener("pointermove", (event) => {
    if (!dragging) return
    const delta = startY - event.clientY
    setHeight(startHeight + delta)
  })

  const finishDrag = () => {
    if (!dragging) return
    dragging = false
    panel.classList.remove("atlas-dragging")

    const height = sheet.offsetHeight
    const threshold = window.innerHeight * 0.28
    if (height < threshold) {
      panel.classList.remove("atlas-mobile-panel-open")
      sheet.style.height = "0px"
    } else {
      panel.classList.add("atlas-mobile-panel-open")
      setHeight(Math.min(Math.max(height, 220), Math.min(window.innerHeight * 0.62, 420)))
    }
  }

  sheet.addEventListener("pointerup", finishDrag)
  sheet.addEventListener("pointercancel", finishDrag)
  sheet.dataset.dragBound = "true"
}

window.addEventListener("resize", setupMobileSheetDrag)
document.addEventListener("DOMContentLoaded", setupMobileSheetDrag)
document.addEventListener("phx:page-loading-stop", setupMobileSheetDrag)
