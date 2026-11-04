---
name: web-performance-optimization
description: >-
  Performance optimization, Leaflet map marker rendering, DOM batching, CSS/SVG infographic rendering, and client caching standards for the web management consoles.
---

# Web Performance & UI Optimization Guide

This skill provides optimization patterns for high-performance rendering across the web management consoles (`web/admin/`, `web/inspector/`, `web/it-admin/`).

---

## 1. Leaflet Map & GPS Tracking Performance

- **Layer Group Pooling**:
  Use dedicated `L.layerGroup()` instances for distinct data layers (`layer` for guard markers, `siteLayer` for deployment sites, `historyLayer` for breadcrumb trails).
- **Marker Re-use vs. Recreation**:
  When updating live guard positions in `web/js/live-tracking.js`, never destroy and re-create existing DOM markers on every poll or broadcast. Update their coordinates smoothly via `marker.setLatLng([newLat, newLng])` or `LiveMarkerMotion` interpolation to eliminate map jitter and excessive DOM redraws.
- **Pin Layer Cleanup**:
  When deployment sites or guards disappear from the filtered snapshot, remove individual layers via `layer.removeLayer(marker)` and prune the map cache.

---

## 2. Infographic & Dashboard Rendering

- **CSS Conic-Gradient Donuts**:
  Render donut charts (`#contractDonut`, `#attendanceDonut` in `web/admin/dashboard.html`) using hardware-accelerated CSS `conic-gradient()` with a centered `.ig-donut-hole` instead of heavy external charting libraries.
- **Bounded Containers for Heavy Lists**:
  Wrap large repetitive lists (such as `#deploymentInfographicList` or `#pmTable`) in bounded scroll containers (e.g., `max-height: 460px; overflow-y: auto;`) to prevent excessive reflows of the entire viewport.
- **Debounced Filters**:
  Debounce rapid keyboard inputs on search bars (`#guardSearch`, `#deploymentSearch`, `#pmSearch`) by `200–300ms` before re-filtering large datasets in memory.

---

## 3. Font & Asset Weight Management

- **Material Symbols Font Subsetting**:
  Do not load the full 2.5 MB Google Material Symbols web font.
  Use the bundled font subset (`web/assets/fonts/MaterialSymbolsRounded-Regular.woff2`, 10.2 KB) supporting the 52 symbols documented in `web/assets/fonts/material-symbols-rounded.json`.
- **Validation**:
  Always verify icons with `node web/tests/google_icons_test.js` to ensure zero missing glyphs.
