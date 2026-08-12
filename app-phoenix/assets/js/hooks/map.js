import maplibregl from "../../vendor/maplibre-gl"

// Hardcoded OSM raster fallback — used when no TILES_URL is configured.
// Matches the Rails JS controller's OSM_RASTER_FALLBACK byte-for-byte.
const OSM_RASTER_FALLBACK = {
  version: 8,
  sources: {
    osm: {
      type: "raster",
      tiles: ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
      tileSize: 256,
      attribution: "© OpenStreetMap contributors"
    }
  },
  layers: [{ id: "osm", type: "raster", source: "osm" }]
}

export default {
  mounted() {
    const tilesUrl = this.el.dataset.tilesUrl
    const theme = this.el.dataset.theme || "forest-patina"
    const initialCenter = JSON.parse(this.el.dataset.center || "[10.4515, 51.1657]")
    const initialZoom = parseFloat(this.el.dataset.zoom || "5")

    const style = tilesUrl ? tilesUrl : OSM_RASTER_FALLBACK

    this.map = new maplibregl.Map({
      container: this.el,
      style: style,
      center: initialCenter,
      zoom: initialZoom
    })

    // Match Rails: controls bottom-right, scale bottom-left.
    this.map.addControl(new maplibregl.NavigationControl({
      showCompass: true,
      visualizePitch: true
    }), "bottom-right")
    this.map.addControl(new maplibregl.ScaleControl({
      maxWidth: 120,
      unit: "metric"
    }), "bottom-left")
    this.resultMarkers = []

    this.clearResultMarkers = () => {
      this.resultMarkers.forEach((m) => m.remove())
      this.resultMarkers = []
    }

    // Report the viewport after every pan/zoom so the server can scope search
    // to what is on screen. `moveend` (not `move`) keeps this to one message
    // per gesture rather than one per frame.
    // `eventData` passed to flyTo comes back on the resulting moveend, which is
    // how a flight we started is told apart from a pan the user made. Both
    // report their bounds; only a user pan re-runs the search.
    this.reportViewport = (event) => {
      const b = this.map.getBounds()
      this.pushEvent("viewport_changed", {
        bbox: [b.getWest(), b.getSouth(), b.getEast(), b.getNorth()],
        programmatic: Boolean(event && event.atlasProgrammatic)
      })
    }
    this.map.on("moveend", this.reportViewport)
    this.map.once("load", this.reportViewport)

    this.handleEvent("map:fly_to", ({ lat, lon, zoom }) => {
      this.map.flyTo({ center: [lon, lat], zoom: zoom || 14 }, { atlasProgrammatic: true })
    })

    // One event owns the whole result-marker set. Replacing wholesale (rather
    // than clear + add) means a pan-triggered refresh cannot race a selection
    // and leave the map bare.
    this.handleEvent("map:set_results", ({ points }) => {
      this.clearResultMarkers()

      ;(points || []).forEach((p) => {
        const marker = new maplibregl.Marker({ element: resultPin(p.label) })
          .setLngLat([p.lon, p.lat])
          .setPopup(
            new maplibregl.Popup({ offset: 14, maxWidth: "320px", className: "apo-poi-popup" })
              .setHTML(resultPopupHTML(p))
          )
          .addTo(this.map)
        this.resultMarkers.push(marker)
      })
    })


    this.routeGeoJSON = null

    this.handleEvent("map:draw_route", ({ geojson }) => {
      this.routeGeoJSON = geojson
      this._renderRoute()
    })

    // Pick-point flow: when the user clicks the pin button next to From/To,
    // the LiveView pushes `map:enter_picker` with `{field}`. We arm a one-shot
    // click listener; on next map click we push `point_picked` back with the
    // coords and reset cursor.
    this.activePicker = null
    this._pickerClickHandler = null
    this._tilesUrl = this.el.dataset.tilesUrl || null

    this.handleEvent("map:enter_picker", ({ field }) => {
      if (!field) return

      // If already arming, replace the field but reuse the same handler.
      this.activePicker = field
      this.map.getCanvas().style.cursor = "crosshair"

      if (this._pickerClickHandler) return

      this._pickerClickHandler = (e) => {
        const field = this.activePicker
        if (!field) return
        const { lng, lat } = e.lngLat
        this.activePicker = null
        this.map.getCanvas().style.cursor = ""
        this.map.off("click", this._pickerClickHandler)
        this._pickerClickHandler = null
        this.pushEvent("point_picked", { field, lat, lon: lng })
      }

      this.map.on("click", this._pickerClickHandler)
    })

    this.handleEvent("map:set_style", ({ url }) => {
      this._tilesUrl = url || null
      const nextStyle = url ? url : OSM_RASTER_FALLBACK

      // Persist what we want to re-add on the new style. A style swap destroys
      // marker DOM, so the set has to be rebuilt rather than left dangling.
      const savedMarkers = this.resultMarkers.map((m) => {
        const lngLat = m.getLngLat()
        const popup = m.getPopup()
        return { lat: lngLat.lat, lon: lngLat.lng, text: popup ? popup.getElement()?.textContent : null }
      })

      this.clearResultMarkers()

      const onStyle = () => {
        // The accent is re-read here on purpose: a style swap usually rides
        // along with a light/dark change, which moves --color-accent.
        const accent = getComputedStyle(document.documentElement)
          .getPropertyValue("--color-accent").trim() || "#B86A3A"

        savedMarkers.forEach(({ lat, lon, text }) => {
          const marker = new maplibregl.Marker({ color: accent }).setLngLat([lon, lat])
          if (text) marker.setPopup(new maplibregl.Popup({ offset: 16 }).setText(text))
          marker.addTo(this.map)
          this.resultMarkers.push(marker)
        })
        // Re-add the route source/layer if we had one.
        if (this.routeGeoJSON) this._renderRoute()
      }

      this.map.once("styledata", onStyle)
      this.map.setStyle(nextStyle)
    })
  },

  _renderRoute() {
    const geojson = this.routeGeoJSON
    if (!geojson) return

    if (this.map.getSource("route")) {
      this.map.getSource("route").setData(geojson)
      return
    }

    const addRoute = () => {
      this.map.addSource("route", { type: "geojson", data: geojson })
      this.map.addLayer({
        id: "route-line",
        type: "line",
        source: "route",
        paint: { "line-color": "#3b82f6", "line-width": 4 }
      })
    }

    if (this.map.isStyleLoaded()) {
      addRoute()
    } else {
      this.map.once("load", addRoute)
    }
  },

  destroyed() {
    if (this.map) this.map.remove()
  }
}

// A search pin, styled like the Rails POI marker: an accent dot that reacts to
// the cursor. MapLibre's default marker has no hover affordance at all, so
// nothing told you a pin could be clicked.
function resultPin(label) {
  // Two elements on purpose: MapLibre positions a marker by writing
  // `transform: translate(...)` onto the element it is given, so any hover
  // transform there would replace the translate and fling the pin to the map
  // origin. The outer div stays MapLibre's; the inner dot is ours to animate.
  const el = document.createElement("div")
  el.className = "apo-poi-marker"
  el.title = label || ""

  const dot = document.createElement("span")
  dot.className = "apo-poi-marker-dot"
  el.appendChild(dot)

  return el
}

function escapeAttr(value) {
  return String(value == null ? "" : value).replace(/"/g, "&quot;").replace(/</g, "&lt;")
}

function escapeText(value) {
  const div = document.createElement("div")
  div.textContent = value == null ? "" : String(value)
  return div.innerHTML
}

// A search result knows less than an Overpass POI: Photon returns no tag block,
// so there are no opening hours, phone or website rows to show. The popup lists
// what this result actually carries and omits the rest, rather than rendering a
// scaffold of empty fields.
function infoRow(value) {
  return `<div class="apo-popup-row"><span class="apo-popup-row-value">${escapeText(value)}</span></div>`
}

function resultPopupHTML(p) {
  const rows = []
  if (p.address) rows.push(infoRow(p.address))
  if (p.region) rows.push(infoRow(p.region))
  rows.push(infoRow(`${p.lat.toFixed(5)}, ${p.lon.toFixed(5)}`))

  const footer = p.osm_url
    ? `<footer class="apo-popup-actions">
         <a class="apo-popup-secondary" target="_blank" rel="noopener" href="${escapeAttr(p.osm_url)}">
           <span>View on OpenStreetMap</span>
         </a>
       </footer>`
    : ""

  return `
    <div class="apo-popup">
      <header class="apo-popup-header">
        <div class="apo-popup-name">${escapeText(p.label)}</div>
        <div class="apo-popup-meta">
          <span class="apo-popup-category">${escapeText(p.category)}</span>
        </div>
      </header>
      <div class="apo-popup-rows">${rows.join("")}</div>
      ${footer}
    </div>
  `
}
