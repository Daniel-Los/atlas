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

  const getPeekHeight = () => Math.min(window.innerHeight * 0.46, 380)
  const getFullHeight = () => Math.max(window.innerHeight - 18, 420)

  const setPanelState = (state) => {
    const isOpen = state !== "hidden"
    sheet.dataset.state = state
    panel.classList.toggle("atlas-mobile-panel-open", isOpen)

    if (state === "hidden") {
      sheet.style.height = "0px"
      return
    }

    const nextHeight = state === "fullscreen" ? getFullHeight() : getPeekHeight()
    sheet.style.height = `${nextHeight}px`
  }

  const currentState = () => sheet.dataset.state || "peek"

  let startY = 0
  let startHeight = 0
  let startState = "peek"
  let dragging = false

  const setHeight = (value) => {
    const minH = 200
    const maxH = getFullHeight()
    const next = Math.min(Math.max(value, minH), maxH)
    sheet.style.height = `${next}px`
  }

  sheet.addEventListener("pointerdown", (event) => {
    if (window.innerWidth > 639) return
    if (event.target.closest("button, input, textarea, select, a, label")) return

    dragging = true
    startY = event.clientY
    startHeight = sheet.offsetHeight || getPeekHeight()
    startState = currentState()
    sheet.setPointerCapture?.(event.pointerId)
    panel.classList.add("atlas-dragging")
  })

  sheet.addEventListener("pointermove", (event) => {
    if (!dragging) return
    const delta = startY - event.clientY
    const base = startState === "fullscreen" ? getFullHeight() : getPeekHeight()
    const next = startState === "hidden" ? getPeekHeight() : Math.max(200, Math.min(base + delta, getFullHeight()))
    setHeight(next)
  })

  const finishDrag = () => {
    if (!dragging) return
    dragging = false
    panel.classList.remove("atlas-dragging")

    const height = sheet.offsetHeight || getPeekHeight()
    const fullThreshold = window.innerHeight * 0.72
    const hiddenThreshold = 210

    if (height > fullThreshold) {
      setPanelState("fullscreen")
      return
    }

    if (height < hiddenThreshold) {
      setPanelState("hidden")
      return
    }

    setPanelState("peek")
  }

  sheet.addEventListener("pointerup", finishDrag)
  sheet.addEventListener("pointercancel", finishDrag)
  sheet.dataset.dragBound = "true"
  setPanelState(currentState())
}

window.addEventListener("resize", setupMobileSheetDrag)
document.addEventListener("DOMContentLoaded", setupMobileSheetDrag)
document.addEventListener("phx:page-loading-stop", setupMobileSheetDrag)
