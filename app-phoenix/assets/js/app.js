import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import MapHook from "./hooks/map"
import LogStreamHook from "./hooks/log_stream"

const MobileSheet = {
  mounted() {
    this.panel = this.el.closest(".atlas-side-panel")
    this.handle = this.el.querySelector("[data-sheet-handle]")
    this.state = this.panel?.classList.contains("atlas-mobile-panel-open") ? "entry" : "collapsed"
    this.dragging = false

    this.snapHeights = () => ({
      collapsed: 0,
      entry: Math.max(240, window.innerHeight * 0.3),
      fullscreen: window.innerHeight
    })

    this.setState = (state, animate = true) => {
      if (window.innerWidth > 639) {
        this.el.style.removeProperty("height")
        this.el.dataset.sheetState = ""
        return
      }

      this.state = state
      this.el.dataset.sheetState = state
      this.el.classList.toggle("atlas-sheet-animating", animate)
      this.panel?.classList.toggle("atlas-mobile-panel-open", state !== "collapsed")
      this.el.style.height = `${this.snapHeights()[state]}px`
    }

    this.nearestState = () => {
      const height = this.el.getBoundingClientRect().height
      const snaps = this.snapHeights()
      return Object.entries(snaps).reduce((nearest, [state, snapHeight]) =>
        Math.abs(height - snapHeight) < Math.abs(height - snaps[nearest]) ? state : nearest
      , "collapsed")
    }

    this.onPointerDown = event => {
      if (window.innerWidth > 639 || event.button !== 0) return
      this.dragging = true
      this.startY = event.clientY
      this.startHeight = this.el.getBoundingClientRect().height
      this.el.classList.remove("atlas-sheet-animating")
      this.el.classList.add("atlas-sheet-dragging")
      this.handle?.setPointerCapture(event.pointerId)
    }

    this.onPointerMove = event => {
      if (!this.dragging) return
      const height = Math.max(0, Math.min(window.innerHeight, this.startHeight + this.startY - event.clientY))
      this.el.style.height = `${height}px`
    }

    this.onPointerUp = () => {
      if (!this.dragging) return
      this.dragging = false
      this.el.classList.remove("atlas-sheet-dragging")
      this.setState(this.nearestState())
    }

    this.onResize = () => this.setState(this.state, false)
    this.handle?.addEventListener("pointerdown", this.onPointerDown)
    this.handle?.addEventListener("pointermove", this.onPointerMove)
    this.handle?.addEventListener("pointerup", this.onPointerUp)
    this.handle?.addEventListener("pointercancel", this.onPointerUp)
    window.addEventListener("resize", this.onResize)
    this.setState(this.state, false)
  },

  updated() {
    if (window.innerWidth <= 639 && this.panel?.classList.contains("atlas-mobile-panel-open") && this.state === "collapsed") {
      this.setState("entry")
    }
  },

  destroyed() {
    this.handle?.removeEventListener("pointerdown", this.onPointerDown)
    this.handle?.removeEventListener("pointermove", this.onPointerMove)
    this.handle?.removeEventListener("pointerup", this.onPointerUp)
    this.handle?.removeEventListener("pointercancel", this.onPointerUp)
    window.removeEventListener("resize", this.onResize)
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {Map: MapHook, LogStream: LogStreamHook, MobileSheet}
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
