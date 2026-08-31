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
    this.state = this.panel?.classList.contains("atlas-mobile-panel-open") ? "half" : "collapsed"
    this.dragging = false

    this.snapHeights = () => ({
      collapsed: 0,
      half: window.innerHeight * 0.5,
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

    this.onPointerDown = event => {
      if (window.innerWidth > 639 || event.button !== 0) return
      if (event.target.closest("button, input, textarea, select, a, label")) return
      this.dragging = true
      this.startState = this.state
      this.startY = event.clientY
      this.lastY = event.clientY
      this.startHeight = this.el.getBoundingClientRect().height
      this.el.classList.remove("atlas-sheet-animating")
      this.el.classList.add("atlas-sheet-dragging")
      this.el.setPointerCapture?.(event.pointerId)
    }

    this.onPointerMove = event => {
      if (!this.dragging) return
      this.lastY = event.clientY
      const height = Math.max(0, Math.min(window.innerHeight, this.startHeight + this.startY - event.clientY))
      this.el.style.height = `${height}px`
    }

    this.onPointerUp = () => {
      if (!this.dragging) return
      this.dragging = false
      this.el.classList.remove("atlas-sheet-dragging")
      const nudge = this.startY - this.lastY
      let state = this.startState

      // A small deliberate nudge advances or retreats one snap point. This
      // keeps fullscreen -> half and half -> collapsed responsive without
      // requiring the sheet to cross an arbitrary height threshold.
      if (Math.abs(nudge) >= 12) {
        if (nudge > 0) {
          state = this.startState === "collapsed" ? "half" : "fullscreen"
        } else {
          state = this.startState === "fullscreen" ? "half" : "collapsed"
        }
      }

      this.setState(state)
      this.pushEvent("set_mobile_panel_state", {open: state !== "collapsed"})
    }

    this.onResize = () => this.setState(this.state, false)
    this.el.addEventListener("pointerdown", this.onPointerDown)
    this.el.addEventListener("pointermove", this.onPointerMove)
    this.el.addEventListener("pointerup", this.onPointerUp)
    this.el.addEventListener("pointercancel", this.onPointerUp)
    window.addEventListener("resize", this.onResize)
    this.setState(this.state, false)
  },

  updated() {
    if (window.innerWidth > 639) return
    const open = this.panel?.classList.contains("atlas-mobile-panel-open")
    if (!open) {
      this.setState("collapsed", false)
    } else if (this.state === "collapsed") {
      this.setState("half", false)
    } else {
      // LiveView patches can replace the inline style; always restore the
      // active snap height after an icon/tab click.
      this.setState(this.state, false)
    }
  },

  destroyed() {
    this.el.removeEventListener("pointerdown", this.onPointerDown)
    this.el.removeEventListener("pointermove", this.onPointerMove)
    this.el.removeEventListener("pointerup", this.onPointerUp)
    this.el.removeEventListener("pointercancel", this.onPointerUp)
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
