# Pool Placement Planner — iPadOS App Plan

Plan for turning the existing single-file web app (`index.html`, Leaflet + vanilla JS)
into a native iPadOS app, built locally on a Mac with Xcode.

**Audience: anyone in the US or Canada planning a pool placement.** The web app was
built around one Quebec municipality's bylaws (1.5 m setbacks, 15% lot coverage,
1 m equipment clearance). Setback and barrier rules vary by state/province *and* by
municipality, so the app hardcodes **no** jurisdiction's rules: every rule is a
user-editable number, and the app's job is to measure and visualize against whatever
rules the user enters from their local bylaw/zoning code.

## 1. What the web app does today (feature inventory)

Everything below must survive the port — this is the checklist we build against.
Items marked ⚙ are Quebec-specific *values* today that become user-configurable
settings in the app.

| Area | Features |
|---|---|
| Map | Esri satellite base layer, optional Google/Mapbox layers (user API key), custom XYZ/WMTS layers, address geocoding (Nominatim) |
| Pool | Oval / round / rectangle shapes, ft dimensions, presets, rotation slider, drag handle to move, double-tap to jump |
| Compliance | ⚙ Property-line setback + structure setback (sliders), distance lines to two nearest lot edges and each structure, red when violating, ⚙ 15% lot coverage rule, ⚙ 1 m equipment clearance rule |
| Drawing | Lot outline (click corners, drag to adjust), multiple structure outlines, per-vertex editing |
| Annotations | Equipment pins (set / heat pump / pump / filter) with live distance readouts; safety pins (ladder / gate / opening); draggable name labels |
| Measure | Point-to-point measure with magnetic snapping to pool/lot/structure edges and pins |
| Site plan | Image overlay with scale, rotation, opacity, white backing sheet, drag to position |
| Scenarios | Named save/restore of shape+size+rotation+buffers+position |
| Output | PNG export with scale bar (permit-ready), clean view, info box |
| Misc | EN/FR toggle, ⚙ metric-only distances, line width / label size / opacity controls, per-location persistence (localStorage) |

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

- **Apple satellite imagery for free** — no Esri/Google/Mapbox keys, high-res across
  the US and Canada, legally clean, and capturable in exports via `MKMapSnapshotter`
  (kills the whole "Google can't be exported" problem class).
- **Touch-first editing** — drag pool/vertices/pins with `DragGesture`, pinch-rotate
  the pool directly, Apple Pencil hover + precision for corner placement.
- **Real files** — site plans imported from Files/Photos (including **PDF surveys**,
  which the web app can't take), exports written as PDF/PNG straight to Files/Share Sheet.
- **Robust persistence** — SwiftData instead of evictable localStorage; iCloud sync of
  projects across devices comes nearly free later.
- Offline map caching, proper undo/redo, localization via String Catalogs.

Decision: **Option B**, with the geometry ported first and verified against the web
app's numbers before any UI work.

## 3. Jurisdiction-agnostic design (US + Canada)

The core principle: **the app is a measuring tool, not a rulebook.** It never claims
to know local law — it measures precisely against rules the user supplies, and makes
violations impossible to miss.

### Rule profiles

Each project has an editable **Rule Profile** — a named set of numeric rules:

| Rule | Default | Notes |
|---|---|---|
| Property-line setback | 5 ft / 1.5 m | Distance from pool wall (or water's edge — user picks the reference) to lot lines |
| Structure setback | 5 ft / 1.5 m | Pool to dwelling/accessory buildings |
| Equipment clearance from pool | 3 ft / 1 m | Anti-climb rule; some codes also set equipment-to-lot-line — supported as its own rule |
| Equipment setback from lot line | off | Optional; common in both countries |
| Max lot coverage | off | Some municipalities cap accessory-structure coverage (the web app's 15%); off by default since many don't |
| Easement/utility buffer | off | Optional extra polygon type with its own setback (see below) |

- Defaults are deliberately common-but-conservative starting points, clearly labeled
  "example — verify with your municipality," never presented as *the* rule.
- Every rule can be toggled off (grayed out of the readout) so the display only shows
  checks that apply locally.
- Profiles are nameable and reusable across projects ("My town 2026").
- A "measurement reference" setting covers the US/Canada split on whether setbacks
  are measured to the pool **wall** or the **water's edge** (affects inground pools
  with coping/decks).

### Units

- **All internal math stays in meters** (the ported geometry core is SI).
- **Display units are a per-project choice: Imperial (ft/in), Metric (m), or Mixed**
  (pool dims in ft, setbacks in m — the web app's convention, common in Canada).
- Every input and label formats through one `UnitFormatter`; US users never see a
  meter, metric users never see a foot.

### Everything else that generalizes

- **Start location**: user's current location (CoreLocation, with permission) instead
  of a hardcoded town; address search via CLGeocoder covers all of US/Canada.
- **Drawn layers generalize**: beyond lot + structures, allow an "other boundary"
  polygon type (easements, septic fields, overhead wire corridors) with an optional
  per-polygon setback — this covers most "I didn't know that restriction existed"
  cases without special-casing any of them.
- **Pool types**: presets grouped as above-ground (the current ovals/rounds) and
  inground rectangles (e.g. 12×24, 16×32, 18×36, 20×40 ft); shapes themselves are
  already generic.
- **Safety/barrier pins stay generic** (ladder, gate, self-closing gate, door alarm,
  fence opening) — barrier *requirements* differ everywhere, so pins are labels the
  user places to document their compliance story, not validated rules.
- **Localization**: EN + FR at launch (FR already exists in the web app's `T` table);
  Spanish is a straightforward later addition via the String Catalog.
- **Disclaimer** on every export and in-app: "Planning aid, not a survey. Verify
  requirements with your local building/zoning authority." (Ported from the web
  footer, made jurisdiction-neutral.)

## 4. Architecture

```
PoolPlanner (SwiftUI, iPadOS 17+)
├── Model (SwiftData)
│   ├── Project        — location name, coordinate, unit preference, one per property
│   ├── RuleProfile    — named set of editable rules (§3), attached to project
│   ├── Scenario       — shape, dims, rotation, center; many per project
│   ├── LotOutline     — [Coordinate]
│   ├── Structure      — name, [Coordinate]; many per project
│   ├── BoundaryZone   — easement/other polygon, optional own setback
│   ├── Annotation     — kind (equipment/safety), coordinate, label offset
│   └── SitePlan       — image data (or PDF page), center, width, rotation, opacity, whiteBacking
├── Geometry (pure Swift, no UIKit — unit-testable, all SI)
│   ├── LocalProjection      (llToXY / xyToLL, port of web code)
│   ├── PoolShape            (shapePoints for oval/round/rect)
│   ├── Distances            (distPointSeg, closestPtSeg, pointInPoly, polygonArea)
│   ├── ComplianceEngine     (evaluates the active RuleProfile → list of checks + pass/fail + gap)
│   └── Snapper              (magnetic snapping, pixel-threshold in screen space)
├── Map layer
│   ├── MapView              — MKMapView via UIViewRepresentable (satellite/hybrid)
│   ├── Overlay renderers    — pool polygon, buffers, lot, structures, zones, distance
│   │                          lines, labels (custom MKOverlayRenderer / CALayer)
│   └── SitePlanOverlay      — custom MKOverlay drawing the georeferenced image
├── UI (SwiftUI)
│   ├── Sidebar / inspector  — collapsible iPad sidebar (current left panel)
│   ├── Rule profile editor  — the §3 rules, with on/off toggles and unit-aware fields
│   ├── Toolbars             — draw lot / structure / zone / measure / add pin modes
│   ├── Scenario switcher
│   └── Export sheet
└── Services
    ├── Geocoder             — CLGeocoder (US/Canada coverage, replaces Nominatim)
    ├── UnitFormatter        — single source of truth for ft/in ↔ m display (§3)
    ├── Exporter             — MKMapSnapshotter + Core Graphics overlay redraw → PNG/PDF + scale bar
    └── Localization         — String Catalog, EN + FR (port the existing T table)
```

Why `MKMapView` (UIKit) and not SwiftUI `Map`: we need custom overlay renderers,
gesture interception during draw modes, tile-level control, and snapshotting —
SwiftUI's `Map` doesn't expose enough yet. One `UIViewRepresentable` wrapper isolates it.

Key design rules carried over from the web app: **all geometry runs in a local
metric XY frame** anchored at a reference coordinate (same flat-earth projection),
so every distance/area/snap computation is identical to the verified web behavior —
and the **ComplianceEngine consumes a RuleProfile**, never constants, so adding a
rule type later touches one enum, not the whole app.

## 5. Build phases

Each phase ends runnable on the iPad. Estimates assume Claude Code doing the work
with you reviewing on-device.

### Phase 0 — Project setup (½ day)
- Xcode project `PoolPlanner`, SwiftUI lifecycle, iPadOS 17 target, portrait+landscape.
- Repo restructure: keep `index.html` at root (GitHub Pages stays live as the web
  reference implementation); app lives in `ios/`.
- Run on your iPad via cable (free provisioning works; see §7).

### Phase 1 — Geometry core + parity tests (1 day)
- Port projection, shapes, distances, area to a `Geometry` module; build
  `ComplianceEngine` around a `RuleProfile` input from day one.
- `UnitFormatter` with imperial/metric/mixed modes, unit-tested.
- Unit tests with fixtures **generated from the web app** (dump a few known
  configurations from the browser console; assert Swift matches to the cm).
- This is the highest-value/lowest-risk chunk — do it before any UI exists.

### Phase 2 — Map + pool (2–3 days)
- Satellite map, CLGeocoder address search, start at user location, double-tap to
  place pool.
- Pool overlay (three shapes), drag handle, rotation via slider **and** two-finger
  rotate gesture, dimension controls, above-ground + inground presets.
- Unit preference picker; live readout panel (dims, area) in chosen units.

### Phase 3 — Lot, structures, rules (2–3 days)
- Draw modes: tap corners → finish; draggable vertex handles (44 pt touch targets —
  bigger than the web's, this is finger territory).
- Rule profile editor (§3) with toggleable rules and unit-aware inputs.
- Distance lines to two nearest lot edges + per-structure nearest gap, labels,
  red-on-violation, type-a-number-to-nudge from the readout.
- Lot coverage % (when enabled) and inside-lot checks.

### Phase 4 — Pins, zones, measure, scenarios (2 days)
- Equipment + safety annotations with live distance labels driven by the rule
  profile, drag, tap to delete, draggable name labels.
- Boundary zones (easements etc.) with optional per-zone setback.
- Measure tool with magnetic snapping (port `snapPoint`, threshold in points).
- Scenario save/switch (SwiftData), per-project persistence replacing localStorage.

### Phase 5 — Site plan overlay + export (2–3 days)
- Import image **or PDF** from Files/Photos; scale/rotate/opacity/white-backing
  controls; drag to georeference. Pinch-to-scale directly on the overlay.
- Export: `MKMapSnapshotter` base + Core Graphics redraw of all overlays + scale bar
  → PNG and **PDF** to the share sheet, with a compliance summary block (each enabled
  rule, measured value, pass/fail) — useful for any permit office. Unlike the web
  app, the site plan overlay **is** included, and so is whatever imagery is showing.
- Clean view (hide handles) as an export option rather than a mode.

### Phase 6 — Polish + distribution (ongoing)
- FR localization (port the `T` table into a String Catalog), undo/redo
  (`UndoManager`), Pencil hover previews for vertex placement, haptics on snap.
- Optional: iCloud sync (CloudKit via SwiftData), custom tile layers for areas where
  Apple imagery is stale (MKTileOverlay + user-supplied Mapbox key — same escape
  hatch the web app has), Spanish localization.

Total to feature parity + generalization: **~2 weeks of build sessions**, usable
on-device from Phase 2.

## 6. Porting notes / gotchas

- **Units**: internal math is meters everywhere; *display* goes through
  `UnitFormatter` per the project's unit preference. Keep the web app's formatters as
  the metric path (`round05` = nearest 5 cm); imperial path rounds to the nearest
  inch. Never store display units in the model — store meters.
- **Rotation slider is 0–180°** in the web app (shapes are symmetric); keep that,
  but the rotate gesture should still normalize into it.
- **Snapping threshold is 14 px** in web; use ~20 pt on touch, ~10 pt with Pencil.
- **Nominatim → CLGeocoder**: rate-limited but fine for interactive use, covers
  US + Canada well, and removes the Nominatim usage-policy concern.
- **No rule constants in code**: the web app's `EQUIP_MIN_M = 1` and
  `MAX_COVERAGE_PCT = 15` become RuleProfile defaults, nothing more. Grep-able check
  before ship: no setback/coverage literals outside the default profile.
- **Imagery quality varies by neighborhood** in both countries; verify Apple
  satellite on a few sample addresses early in Phase 2. The Mapbox tile-layer
  escape hatch in Phase 6 covers stale areas.
- **Disclaimer** must carry over into the app and onto every export, worded
  jurisdiction-neutrally (§3).

## 7. What you need on the Mac

- Xcode 16+ (App Store), signed in with your Apple ID (Settings → Accounts).
- Your iPad on the same Apple ID, Developer Mode enabled
  (Settings → Privacy & Security → Developer Mode), connected once by cable to trust.
- **Free tier**: install to your own iPad, app re-signs every 7 days — fine for
  development. **Apple Developer Program ($99/yr)**: only needed for TestFlight /
  App Store / 1-year signing. Not required to start.
- No API keys needed at all (Apple Maps + CLGeocoder replace Esri/Google/Mapbox/Nominatim).

## 8. First session locally (the concrete kickoff)

1. `mkdir ios` — create the Xcode project there (Claude Code can generate the
   project via `xcodegen` or a checked-in `project.yml`, so the project file is
   reviewable text, not binary).
2. Port `Geometry` + `RuleProfile` + `UnitFormatter` with parity tests (Phase 1),
   run `xcodebuild test` headless.
3. Get the satellite map + a draggable oval pool on your iPad screen (Phase 2 start).
