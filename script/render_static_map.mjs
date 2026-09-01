#!/usr/bin/env node
// Headless renderer for atlas static maps.
//
// Setup (one-off):
//   cd atlas && npm install --save-dev playwright && npx playwright install chromium
//
// Run (atlas must be up on :8484):
//   node script/render_static_map.mjs \
//     --lat 52.520 --lon 13.405 --zoom 12 --width 1200 --height 630 \
//     --title "Berlin Mitte" --subtitle "Saturday walk" \
//     --out script/out/berlin.png
//
// With a Valhalla route polyline (precision-6, URL-encoded):
//   ROUTE=$(curl -s "http://localhost:8484/api/v1/route?from_lat=52.51&from_lon=13.39&to_lat=52.53&to_lon=13.42&mode=auto" | jq -r '.trip.legs[0].shape')
//   node script/render_static_map.mjs --route "$ROUTE" --fit 1 --out script/out/route.png

import { chromium } from "playwright"
import { mkdir, writeFile } from "node:fs/promises"
import { dirname, resolve } from "node:path"

const DEFAULTS = {
  base:     process.env.ATLAS_URL || "http://localhost:8484",
  lat:      "51.1657",
  lon:      "10.4515",
  zoom:     "5",
  width:    "800",
  height:   "600",
  theme:    "light",
  title:    "",
  subtitle: "",
  brand:    "Dawarich Atlas",
  route:    "",
  fit:      "0",
  out:      "script/out/map.png",
  timeout:  "30000"
}

function parseArgs(argv) {
  const out = { ...DEFAULTS }
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (a.startsWith("--")) {
      const key = a.slice(2)
      const val = argv[i + 1]
      if (val === undefined || val.startsWith("--")) {
        out[key] = "1"
      } else {
        out[key] = val
        i++
      }
    }
  }
  return out
}

async function render(opts) {
  const params = new URLSearchParams({
    lat:      opts.lat,
    lon:      opts.lon,
    zoom:     opts.zoom,
    width:    opts.width,
    height:   opts.height,
    theme:    opts.theme,
    title:    opts.title,
    subtitle: opts.subtitle,
    brand:    opts.brand,
    route:    opts.route,
    fit:      opts.fit
  })
  const url = `${opts.base}/static_map?${params.toString()}`

  const browser = await chromium.launch({ headless: true })
  try {
    const ctx = await browser.newContext({
      viewport:           { width: Number(opts.width), height: Number(opts.height) },
      deviceScaleFactor:  Number(opts.scale || 2),
      reducedMotion:      "reduce"
    })
    const page = await ctx.newPage()

    page.on("console", (msg) => {
      if (msg.type() === "error") console.error("[browser]", msg.text())
    })

    console.error(`→ ${url}`)
    await page.goto(url, { waitUntil: "networkidle", timeout: Number(opts.timeout) })
    await page.waitForFunction(() => window.__atlasStaticReady === true, null, { timeout: Number(opts.timeout) })
    await page.waitForTimeout(150)

    const outPath = resolve(opts.out)
    await mkdir(dirname(outPath), { recursive: true })
    const buf = await page.screenshot({ type: "png", fullPage: false, omitBackground: false })
    await writeFile(outPath, buf)
    console.error(`✓ wrote ${outPath} (${buf.byteLength} bytes)`)
  } finally {
    await browser.close()
  }
}

const opts = parseArgs(process.argv.slice(2))
render(opts).catch((err) => {
  console.error(err)
  process.exit(1)
})
