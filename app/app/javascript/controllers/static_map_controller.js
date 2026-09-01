import { Controller } from "@hotwired/stimulus"
import maplibregl from "maplibre-gl"
import { Protocol } from "pmtiles"
import { layers as protomapsLayers } from "protomaps-themes-base"
import { decodePolyline6 } from "../lib/polyline6"

const OSM_RASTER_FALLBACK = {
  version: 8,
  sources: {
    osm: {
      type: "raster",
      tiles: ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
      tileSize: 256
    }
  },
  layers: [{ id: "osm", type: "raster", source: "osm" }]
}

export default class extends Controller {
  static targets = ["canvas"]
  static values = {
    tilesUrl: String,
    theme:    { type: String, default: "light" },
    lat:      Number,
    lon:      Number,
    zoom:     Number,
    route:    String,
    fit:      Boolean
  }

  connect() {
    if (!maplibregl.protocolRegistered) {
      maplibregl.addProtocol("pmtiles", new Protocol().tile)
      maplibregl.protocolRegistered = true
    }

    this.map = new maplibregl.Map({
      container: this.canvasTarget,
      style: this.buildStyle(),
      center: [this.lonValue || 10.4515, this.latValue || 51.1657],
      zoom: this.zoomValue || 5,
      attributionControl: false,
      interactive: false,
      fadeDuration: 0,
      preserveDrawingBuffer: true
    })

    this.map.on("load", () => {
      this.drawRoute()
      this.signalReadyWhenIdle()
    })
  }

  buildStyle() {
    const url = this.tilesUrlValue
    if (!url) return OSM_RASTER_FALLBACK
    if (url.startsWith("pmtiles://") || url.endsWith(".pmtiles")) return this.protomapsStyle()
    return url
  }

  protomapsStyle() {
    return {
      version: 8,
      glyphs: "https://protomaps.github.io/basemaps-assets/fonts/{fontstack}/{range}.pbf",
      sprite: `https://protomaps.github.io/basemaps-assets/sprites/v4/${this.themeValue || "light"}`,
      sources: {
        protomaps: {
          type: "vector",
          url: this.protocolUrl()
        }
      },
      layers: protomapsLayers("protomaps", this.themeValue || "light")
    }
  }

  protocolUrl() {
    const url = this.tilesUrlValue
    if (url.startsWith("pmtiles://")) return url
    if (url.endsWith(".pmtiles"))     return `pmtiles://${url}`
    return url
  }

  drawRoute() {
    const encoded = this.routeValue
    if (!encoded) return
    const coords = decodePolyline6(encoded)
    if (coords.length < 2) return

    const geojson = { type: "Feature", geometry: { type: "LineString", coordinates: coords } }
    this.map.addSource("route", { type: "geojson", data: geojson })
    this.map.addLayer({
      id: "route-casing", source: "route", type: "line",
      layout: { "line-cap": "round", "line-join": "round" },
      paint: { "line-color": "#ffffff", "line-width": 7 }
    })
    this.map.addLayer({
      id: "route-line", source: "route", type: "line",
      layout: { "line-cap": "round", "line-join": "round" },
      paint: { "line-color": "#2F5D3E", "line-width": 4 }
    })

    const start = coords[0]
    const end   = coords[coords.length - 1]
    this.addEndpoint(start, "#3D6F7A")
    this.addEndpoint(end,   "#9C3A2A")

    if (this.fitValue) {
      const lons = coords.map(c => c[0])
      const lats = coords.map(c => c[1])
      this.map.fitBounds(
        [[Math.min(...lons), Math.min(...lats)], [Math.max(...lons), Math.max(...lats)]],
        { padding: 60, duration: 0 }
      )
    }
  }

  addEndpoint([lon, lat], color) {
    const el = document.createElement("div")
    el.style.cssText = `width: 14px; height: 14px; border-radius: 50%; background: ${color}; border: 3px solid #fff; box-shadow: 0 0 0 1px rgba(0,0,0,0.2);`
    new maplibregl.Marker({ element: el }).setLngLat([lon, lat]).addTo(this.map)
  }

  signalReadyWhenIdle() {
    const markReady = () => {
      document.body.setAttribute("data-ready", "true")
      window.__atlasStaticReady = true
    }
    if (this.map.loaded() && !this.map.isMoving() && !this.map.isZooming() && !this.map.isRotating()) {
      this.map.once("idle", markReady)
    } else {
      this.map.once("idle", markReady)
    }
  }
}
