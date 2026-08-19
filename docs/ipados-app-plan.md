# Pool Placement Planner — iPadOS App Plan

Plan for turning the existing single-file web app (`index.html`, Leaflet + vanilla JS)
into a native iPadOS app, built locally on a Mac with Xcode.

## 1. What the web app does today (feature inventory)

Everything below must survive the port — this is the checklist we build against.

| Area | Features |
|---|---|
| Map | Esri satellite base layer, optional Google/Mapbox layers (user API key), custom XYZ/WMTS layers, address geocoding (Nominatim) |
| Pool | Oval / round / rectangle shapes, ft dimensions, presets, rotation slider, drag handle to move, double-tap to jump |
| Compliance | Property-line setback + structure setback (m, sliders), distance lines to two nearest lot edges and each structure, red when violating, 15% lot coverage rule, equipment ≥ 1 m anti-climb rule |
| Drawing | Lot outline (click corners, drag to adjust), multiple structure outlines, per-vertex editing |
| Annotations | Equipment pins (set / heat pump / pump / filter) with live distance readouts; safety pins (ladder / gate / opening); draggable name labels |
| Measure | Point-to-point measure with magnetic snapping to pool/lot/structure edges and pins |
| Site plan | Image overlay with scale (width in m), rotation, opacity, white backing sheet, drag to position |
| Scenarios | Named save/restore of shape+size+rotation+buffers+position |
| Output | PNG export with scale bar (permit-ready), clean view, info box |
| Misc | EN/FR toggle, line width / label size / opacity controls, per-location persistence (localStorage keyed by geocoded location) |

The math core is small and portable: `llToXY` / `xyToLL` (local flat-earth projection),
`distPointSeg`, `closestPtSeg`, `pointInPoly`, `polygonAreaM2`, `shapePoints`, `snapPoint`.
~200 lines of pure geometry that translate 1:1 to Swift.

## 2. Approach decision

Two viable routes:

**A. WKWebView wrapper (Capacitor-style)** — ship the existing HTML inside a shell.
Fast (a day), but: touch UX stays web-grade, no Pencil, PNG export still hits the
canvas-taint limits, localStorage can be evicted by the OS, and it will feel like a
website in a frame. Reasonable only as a stopgap.

**B. Native SwiftUI + MapKit (recommended).** Rewrite the UI natively, port the
geometry core to Swift. Wins that matter for *this* app on *this* device:

- **Apple satellite imagery for free** — no Esri/Google/Mapbox keys, high-res, legally
  clean, and capturable in exports via `MKMapSnapshotter` (kills the whole
  "Google can't be exported" problem class).
- **Touch-first editing** — drag pool/vertices/pins with `DragGesture`, pinch-rotate
  the pool directly, Apple Pencil hover + precision for corner placement.
- **Real files** — site plans imported from Files/Photos (including **PDF surveys**,
  which the web app can't take), exports written as PDF/PNG straight to Files/Share Sheet.
- **Robust persistence** — SwiftData instead of evictable localStorage; iCloud sync of
  projects across devices comes nearly free later.
- Offline map caching, proper undo/redo, EN/FR via String Catalogs.

Decision: **Option B**, with the geometry ported first and verified against the web
app's numbers before any UI work.

## 3. Architecture

```
PoolPlanner (SwiftUI, iPadOS 17+)
├── Model (SwiftData)
│   ├── Project        — location name, coordinate, one per property
│   ├── Scenario       — shape, dims(ft), rotation, buffers, center; many per project
│   ├── LotOutline     — [Coordinate]
│   ├── Structure      — name, [Coordinate]; many per project
│   ├── Annotation     — kind (set/hp/pump/filter/ladder/gate/opening), coordinate, label offset
│   └── SitePlan       — image data (or PDF page), center, widthMeters, rotation, opacity, whiteBacking
├── Geometry (pure Swift, no UIKit — unit-testable)
│   ├── LocalProjection      (llToXY / xyToLL, port of web code)
│   ├── PoolShape            (shapePoints for oval/round/rect)
│   ├── Distances            (distPointSeg, closestPtSeg, pointInPoly, polygonArea)
│   ├── ComplianceEngine     (setback checks, coverage %, equipment ≥ 1 m)
│   └── Snapper              (magnetic snapping, pixel-threshold in screen space)
├── Map layer
│   ├── MapView              — MKMapView via UIViewRepresentable (satellite/hybrid)
│   ├── Overlay renderers    — pool polygon, buffers, lot, structures, distance lines,
│   │                          labels (custom MKOverlayRenderer or CALayer annotations)
│   └── SitePlanOverlay      — custom MKOverlay drawing the georeferenced image
├── UI (SwiftUI)
│   ├── Sidebar / inspector  — the current left panel, as a collapsible iPad sidebar
│   ├── Toolbars             — draw lot / draw structure / measure / add pin modes
│   ├── Scenario switcher
│   └── Export sheet
└── Services
    ├── Geocoder             — CLGeocoder (replaces Nominatim)
    ├── Exporter             — MKMapSnapshotter + Core Graphics overlay redraw → PNG/PDF + scale bar
    └── Localization         — String Catalog, EN + FR (port the existing T table)
```

Why `MKMapView` (UIKit) and not SwiftUI `Map`: we need custom overlay renderers,
gesture interception during draw modes, tile-level control, and snapshotting —
SwiftUI's `Map` doesn't expose enough yet. One `UIViewRepresentable` wrapper isolates it.

Key design rule carried over from the web app: **all geometry runs in a local
metric XY frame** anchored at a reference coordinate (same flat-earth projection),
so every distance/area/snap computation is identical to the verified web behavior.

## 4. Build phases

Each phase ends runnable on the iPad. Estimates assume Claude Code doing the work
with you reviewing on-device.

### Phase 0 — Project setup (½ day)
- Xcode project `PoolPlanner`, SwiftUI lifecycle, iPadOS 17 target, portrait+landscape.
- Repo restructure: keep `index.html` at root (GitHub Pages stays live as the web
  reference implementation); app lives in `ios/`.
- Run on your iPad via cable (free provisioning works; see §6).

### Phase 1 — Geometry core + parity tests (1 day)
- Port projection, shapes, distances, area, compliance rules to a `Geometry` module.
- Unit tests with fixtures **generated from the web app** (dump a few known
  configurations from the browser console; assert Swift matches to the cm).
- This is the highest-value/lowest-risk chunk — do it before any UI exists.

### Phase 2 — Map + pool (2–3 days)
- Satellite map, CLGeocoder address search, double-tap to place pool.
- Pool overlay (three shapes), drag handle, rotation via slider **and** two-finger
  rotate gesture, dimension controls, presets.
- Live readout panel (dims, area, coverage %).

### Phase 3 — Lot, structures, setbacks (2–3 days)
- Draw modes: tap corners → finish; draggable vertex handles (44 pt touch targets —
  bigger than the web's, this is finger territory).
- Distance lines to two nearest lot edges + per-structure nearest gap, labels,
  red-on-violation, type-a-number-to-nudge from the readout.
- Coverage % and inside-lot checks.

### Phase 4 — Pins, measure, scenarios (2 days)
- Equipment + safety annotations with live distance labels, drag, tap to delete,
  draggable name labels.
- Measure tool with magnetic snapping (port `snapPoint`, threshold in points).
- Scenario save/switch (SwiftData), per-project persistence replacing localStorage.

### Phase 5 — Site plan overlay + export (2–3 days)
- Import image **or PDF** from Files/Photos; scale/rotate/opacity/white-backing
  controls; drag to georeference. Pinch-to-scale directly on the overlay.
- Export: `MKMapSnapshotter` base + Core Graphics redraw of all overlays + scale bar
  → PNG and **PDF** to the share sheet. Unlike the web app, the site plan overlay
  **is** included, and so is whatever imagery is showing.
- Clean view (hide handles) as an export option rather than a mode.

### Phase 6 — Polish + distribution (ongoing)
- FR localization (port the `T` table into a String Catalog), undo/redo
  (`UndoManager`), Pencil hover previews for vertex placement, haptics on snap.
- Optional: iCloud sync (CloudKit via SwiftData), custom tile layers if Apple
  imagery is ever too stale for a lot (MKTileOverlay + user-supplied Mapbox key —
  same escape hatch the web app has).

Total to feature parity: **~2 weeks of build sessions**, usable on-device from Phase 2.

## 5. Porting notes / gotchas

- **Units**: web app mixes ft (pool dims) and m (setbacks, distances). Keep exactly
  that convention — it matches Quebec permit workflows. Formatters: `round05`
  (nearest 5 cm) and the ft formatter port as-is.
- **Rotation slider is 0–180°** in the web app (shapes are symmetric); keep that,
  but the rotate gesture should still normalize into it.
- **Snapping threshold is 14 px** in web; use ~20 pt on touch, ~10 pt with Pencil.
- **Nominatim → CLGeocoder**: CLGeocoder is rate-limited but fine for interactive
  use; it also removes the Nominatim usage-policy concern.
- **Coverage rule (15%) and equipment min (1 m)** are constants in the web app;
  surface them as editable "bylaw settings" per project — municipalities differ.
- **Disclaimer** ("planning aid, not a survey") must carry over into the app and
  onto every export, same as the web footer.
- Apple satellite imagery in the Vaudreuil-Dorion area is current and high-res;
  verify on your actual lot early in Phase 2 before we commit to dropping Esri.

## 6. What you need on the Mac

- Xcode 16+ (App Store), signed in with your Apple ID (Settings → Accounts).
- Your iPad on the same Apple ID, Developer Mode enabled
  (Settings → Privacy & Security → Developer Mode), connected once by cable to trust.
- **Free tier**: install to your own iPad, app re-signs every 7 days — fine for
  development. **Apple Developer Program ($99/yr)**: only needed for TestFlight /
  App Store / 1-year signing. Not required to start.
- No API keys needed at all (Apple Maps + CLGeocoder replace Esri/Google/Mapbox/Nominatim).

## 7. First session locally (the concrete kickoff)

1. `mkdir ios` — create the Xcode project there (Claude Code can generate the
   project via `xcodegen` or a checked-in `project.yml`, so the project file is
   reviewable text, not binary).
2. Port `Geometry` + parity tests (Phase 1), run `xcodebuild test` headless.
3. Get the satellite map + a draggable oval pool on your iPad screen (Phase 2 start).
