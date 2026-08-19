import SwiftUI
import MapKit

// MARK: - Scene model

/// Everything the map renders, precomputed by the model. The coordinator
/// diffs this value and rebuilds overlays/annotations only when it changes.
struct MapScene: Equatable {
    enum ConnectorKind: Equatable {
        case lot, structure, equipmentToPool, equipmentToLot, zone
    }

    struct Connector: Equatable {
        var from: LatLng
        var to: LatLng
        var distM: Double
        var violating: Bool
        var kind: ConnectorKind
    }

    var poolRing: [LatLng]?
    var lot: [LatLng]
    var lotViolating: Bool
    var structures: [[LatLng]]
    var structureViolating: [Bool]
    var draft: [LatLng]
    var drawing: Bool
    var connectors: [Connector]
    var pins: [PlacedPin]
    var measurePoints: [LatLng]
    var measureSnapped: [Bool]
    var displayUnits: UnitSystem
    var sitePlan: SitePlanParams?
    var zones: [BoundaryZone]
    var zoneViolating: [Bool]
    var cleanView: Bool
    var tileTemplate: String?
}

extension PlannerModel {
    var mapScene: MapScene {
        let report = self.report
        var connectors: [MapScene.Connector] = []
        var lotViolating = false
        var structureViolating = structures.map { _ in false }
        var zoneViolating = zones.map { _ in false }

        if let report {
            let ref = report.ref
            let lotSetback = rules.propertyLineSetbackM
            let outside = report.poolCenterInsideLot == false
            lotViolating = report.lotSetbackViolation
            for gap in report.lotEdgeGaps.prefix(2) {
                let c = gap.connector
                let viol = outside || (lotSetback.map { c.d < $0 } ?? false)
                connectors.append(MapScene.Connector(
                    from: Geo.xyToLL(c.from, ref: ref),
                    to: Geo.xyToLL(c.to, ref: ref),
                    distM: c.d, violating: viol, kind: .lot
                ))
            }
            let structSetback = rules.structureSetbackM
            for (i, gap) in report.structureGaps.enumerated() {
                guard let c = gap else { continue }
                let viol = structSetback.map { c.d < $0 } ?? false
                if structureViolating.indices.contains(i) { structureViolating[i] = viol }
                connectors.append(MapScene.Connector(
                    from: Geo.xyToLL(c.from, ref: ref),
                    to: Geo.xyToLL(c.to, ref: ref),
                    distM: c.d, violating: viol, kind: .structure
                ))
            }
            zoneViolating = report.zoneViolations
            for (i, gap) in report.zoneGaps.enumerated() {
                guard let c = gap else { continue }
                connectors.append(MapScene.Connector(
                    from: Geo.xyToLL(c.from, ref: ref),
                    to: Geo.xyToLL(c.to, ref: ref),
                    distM: c.d,
                    violating: report.zoneViolations.indices.contains(i) && report.zoneViolations[i],
                    kind: .zone
                ))
            }
            // Equipment connectors (web refreshEquip): pin → nearest pool wall
            // point, and pin → nearest lot line point when a lot is drawn.
            if let ring = poolRing {
                let poolXY = ring.map { Geo.llToXY($0, ref: ref) }
                let lotXY = lot.count >= 3 ? lot.map { Geo.llToXY($0, ref: ref) } : nil
                for (i, pin) in measuredPins.enumerated() {
                    guard report.equipment.indices.contains(i) else { break }
                    let check = report.equipment[i]
                    let p = Geo.llToXY(pin.position, ref: ref)
                    if let np = Geo.nearestOnPoly(p, poolXY) {
                        connectors.append(MapScene.Connector(
                            from: pin.position,
                            to: Geo.xyToLL(np.c, ref: ref),
                            distM: np.d, violating: check.poolViolation, kind: .equipmentToPool
                        ))
                    }
                    if let lotXY, let nl = Geo.nearestOnPoly(p, lotXY) {
                        connectors.append(MapScene.Connector(
                            from: pin.position,
                            to: Geo.xyToLL(nl.c, ref: ref),
                            distM: nl.d, violating: check.lotViolation, kind: .equipmentToLot
                        ))
                    }
                }
            }
        }

        return MapScene(
            poolRing: poolRing,
            lot: lot,
            lotViolating: lotViolating,
            structures: structures,
            structureViolating: structureViolating,
            draft: draftPoints,
            drawing: drawMode != .none,
            connectors: connectors,
            pins: pins,
            measurePoints: measurePoints,
            measureSnapped: measureSnapped,
            displayUnits: units,
            sitePlan: sitePlan,
            zones: zones,
            zoneViolating: zoneViolating,
            cleanView: cleanView,
            tileTemplate: customTileTemplate
        )
    }
}

// MARK: - Annotations

/// Draggable corner handle of the lot or a structure.
final class VertexAnnotation: NSObject, MKAnnotation {
    enum Kind { case lot, structure, zone }
    let kind: Kind
    let polygonIndex: Int
    let vertexIndex: Int
    dynamic var coordinate: CLLocationCoordinate2D

    init(kind: Kind, polygonIndex: Int, vertexIndex: Int, coordinate: CLLocationCoordinate2D) {
        self.kind = kind
        self.polygonIndex = polygonIndex
        self.vertexIndex = vertexIndex
        self.coordinate = coordinate
    }
}

/// Non-interactive dot marking a draft vertex while drawing.
final class DraftDotAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
}

/// Distance chip at the midpoint of a connector line.
final class DistanceLabelAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    let text: String
    let violating: Bool
    let kind: MapScene.ConnectorKind

    init(coordinate: CLLocationCoordinate2D, text: String, violating: Bool, kind: MapScene.ConnectorKind) {
        self.coordinate = coordinate
        self.text = text
        self.violating = violating
        self.kind = kind
    }
}

/// Draggable equipment/safety pin.
final class PinAnnotation: NSObject, MKAnnotation {
    let pinID: UUID
    let kind: PinKind
    dynamic var coordinate: CLLocationCoordinate2D

    init(pin: PlacedPin) {
        self.pinID = pin.id
        self.kind = pin.kind
        self.coordinate = CLLocationCoordinate2D(latitude: pin.position.lat, longitude: pin.position.lng)
    }
}

/// Dot marking a measure-tool point (orange when it snapped to an edge/pin).
final class MeasureDotAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    let snapped: Bool
    init(coordinate: CLLocationCoordinate2D, snapped: Bool) {
        self.coordinate = coordinate
        self.snapped = snapped
    }
}

// MARK: - Palette (web app colors)

enum Palette {
    static let poolFill = UIColor(red: 0x15 / 255, green: 0x87 / 255, blue: 0xA8 / 255, alpha: 0.55)
    static let poolStroke = UIColor(red: 0x0D / 255, green: 0x6A / 255, blue: 0x85 / 255, alpha: 1)
    static let lot = UIColor(red: 0x2E / 255, green: 0x7D / 255, blue: 0x32 / 255, alpha: 1)
    static let structStroke = UIColor(red: 0x5A / 255, green: 0x3A / 255, blue: 0x99 / 255, alpha: 1)
    static let structFill = UIColor(red: 0x7B / 255, green: 0x4B / 255, blue: 0xC9 / 255, alpha: 1)
    static let warn = UIColor(red: 0xC0 / 255, green: 0x39 / 255, blue: 0x2B / 255, alpha: 1)
    static let ink = UIColor(red: 0x1C / 255, green: 0x27 / 255, blue: 0x33 / 255, alpha: 1)
    static let zone = UIColor(red: 0xD9 / 255, green: 0x82 / 255, blue: 0x2B / 255, alpha: 1)
    static let measure = UIColor(red: 0xFF / 255, green: 0xE4 / 255, blue: 0x5C / 255, alpha: 1)
    static let snap = UIColor(red: 0xE8 / 255, green: 0x59 / 255, blue: 0x0C / 255, alpha: 1)
}

// MARK: - Map view

/// MKMapView wrapper (SwiftUI's Map doesn't expose custom overlay renderers,
/// gesture interception, or snapshotting — see the app plan §4).
///
/// Interactions:
/// - double-tap: place / move the pool there (map's double-tap zoom is suppressed)
/// - single tap while a draw mode is active: add a lot/structure corner
/// - press-and-drag the pool's center handle or a polygon corner: move it
///   (native MKAnnotationView dragging — MapKit arbitrates against map panning)
/// - two-finger rotate starting on the pool: rotate the pool
struct PoolMapView: UIViewRepresentable {
    @ObservedObject var model: PlannerModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.mapType = .satellite
        map.isRotateEnabled = false // keep north-up like the web app
        map.isPitchEnabled = false
        map.showsCompass = false
        map.showsUserLocation = true
        map.delegate = context.coordinator
        // Somewhere reasonable until location/search arrives (continental view).
        map.setRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 45.0, longitude: -95.0),
                span: MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 60)
            ),
            animated: false
        )
        context.coordinator.attachGestures(to: map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.sync(map: map)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        private let model: PlannerModel
        private var lastCameraID: UUID?
        private var lastPlaceToken: UUID?
        private var rotateStartDeg: Double?
        private let handleAnnotation = MKPointAnnotation()
        private var handleOnMap = false
        private var draggingAnnotation = false

        private var lastScene: MapScene?
        private var sceneOverlays: [MKOverlay] = []
        private var sceneAnnotations: [MKAnnotation] = []

        init(model: PlannerModel) {
            self.model = model
        }

        // MARK: gestures

        func attachGestures(to map: MKMapView) {
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            doubleTap.delegate = self
            map.addGestureRecognizer(doubleTap)
            // Suppress the map's built-in double-tap zoom: it may only fire
            // if our recognizer fails.
            requireFailure(of: doubleTap, inSubviewsOf: map)

            let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
            singleTap.numberOfTapsRequired = 1
            singleTap.delegate = self
            map.addGestureRecognizer(singleTap)

            let rotate = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate(_:)))
            rotate.delegate = self
            map.addGestureRecognizer(rotate)
        }

        private func requireFailure(of recognizer: UITapGestureRecognizer, inSubviewsOf view: UIView) {
            for sub in view.subviews {
                for rec in sub.gestureRecognizers ?? [] {
                    if let tap = rec as? UITapGestureRecognizer, tap.numberOfTapsRequired == 2 {
                        tap.require(toFail: recognizer)
                    }
                }
                requireFailure(of: recognizer, inSubviewsOf: sub)
            }
        }

        @objc private func handleDoubleTap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let map = g.view as? MKMapView else { return }
            guard model.drawMode == .none, !model.measureMode else { return }
            let coord = map.convert(g.location(in: map), toCoordinateFrom: map)
            model.setPoolCenter(LatLng(lat: coord.latitude, lng: coord.longitude))
        }

        @objc private func handleSingleTap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let map = g.view as? MKMapView else { return }
            let pt = g.location(in: map)
            let coord = map.convert(pt, toCoordinateFrom: map)
            let ll = LatLng(lat: coord.latitude, lng: coord.longitude)
            if model.measureMode {
                let (snappedLL, didSnap) = snap(ll, tapPoint: pt, on: map)
                model.addMeasurePoint(snappedLL, snapped: didSnap)
            } else if model.drawMode != .none {
                model.addDraftPoint(ll)
            }
        }

        /// Magnetic snapping, ported from the web app's snapPoint: pull a tap
        /// to the nearest pool/lot/structure edge or pin within ~20 screen
        /// points (the web used 14 px for a mouse; fingers get more).
        private func snap(_ ll: LatLng, tapPoint: CGPoint, on map: MKMapView) -> (LatLng, Bool) {
            let threshold: CGFloat = 20
            var best: LatLng?
            var bestPx = threshold

            func consider(_ cand: LatLng) {
                let p = map.convert(CLLocationCoordinate2D(latitude: cand.lat, longitude: cand.lng), toPointTo: map)
                let d = hypot(p.x - tapPoint.x, p.y - tapPoint.y)
                if d < bestPx {
                    bestPx = d
                    best = cand
                }
            }

            var rings: [[LatLng]] = []
            if let ring = model.poolRing { rings.append(ring) }
            if model.lot.count >= 3 { rings.append(model.lot) }
            for s in model.structures where s.count >= 3 { rings.append(s) }
            for ring in rings {
                let xy = ring.map { Geo.llToXY($0, ref: ll) }
                for i in 0..<xy.count {
                    let r = Geo.closestPtSeg(XY(x: 0, y: 0), xy[i], xy[(i + 1) % xy.count])
                    consider(Geo.xyToLL(r.c, ref: ll))
                }
            }
            for zone in model.zones where zone.points.count >= 3 {
                let xy = zone.points.map { Geo.llToXY($0, ref: ll) }
                for i in 0..<xy.count {
                    let r = Geo.closestPtSeg(XY(x: 0, y: 0), xy[i], xy[(i + 1) % xy.count])
                    consider(Geo.xyToLL(r.c, ref: ll))
                }
            }
            for pin in model.pins { consider(pin.position) }
            if let best {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                return (best, true)
            }
            return (ll, false)
        }

        @objc private func handleRotate(_ g: UIRotationGestureRecognizer) {
            switch g.state {
            case .began:
                rotateStartDeg = model.rotationDeg
            case .changed:
                guard let start = rotateStartDeg else { return }
                model.rotationDeg = PlannerModel.normalizeRotation(start + g.rotation * 180 / .pi)
            default:
                rotateStartDeg = nil
            }
        }

        // Only claim gestures that concern the pool; everything else stays map navigation.
        nonisolated func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            MainActor.assumeIsolated {
                guard let map = g.view as? MKMapView else { return false }
                switch g {
                case is UITapGestureRecognizer:
                    return true
                case is UIRotationGestureRecognizer:
                    return isPoint(g.location(in: map), insidePoolOn: map, slopPt: 80)
                default:
                    return true
                }
            }
        }

        nonisolated func gestureRecognizer(
            _ g: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            // Let pool rotation ride along with the map's pinch zoom.
            g is UIRotationGestureRecognizer || other is UIRotationGestureRecognizer
        }

        private func isPoint(_ pt: CGPoint, insidePoolOn map: MKMapView, slopPt: CGFloat) -> Bool {
            guard let ring = model.poolRing else { return false }
            let screen = ring.map {
                let p = map.convert(CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng), toPointTo: map)
                return XY(x: p.x, y: p.y)
            }
            let target = XY(x: pt.x, y: pt.y)
            if Geo.pointInPoly(target, screen) { return true }
            // Forgiving edge slop for finger-sized targets.
            for i in 0..<screen.count {
                if Geo.distPointSeg(target, screen[i], screen[(i + 1) % screen.count]) < slopPt {
                    return true
                }
            }
            return false
        }

        // MARK: model → map

        func sync(map: MKMapView) {
            if let token = model.placeAtCenterToken, token != lastPlaceToken {
                lastPlaceToken = token
                let c = map.centerCoordinate
                DispatchQueue.main.async {
                    self.model.setPoolCenter(LatLng(lat: c.latitude, lng: c.longitude))
                }
            }
            if let kind = model.pendingPinKind {
                let c = map.centerCoordinate
                DispatchQueue.main.async {
                    self.model.pendingPinKind = nil
                    self.model.addPin(kind, at: LatLng(lat: c.latitude, lng: c.longitude))
                }
            }
            syncTileOverlay(map: map)
            if let req = model.cameraRequest, req.id != lastCameraID {
                lastCameraID = req.id
                let region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: req.center.lat, longitude: req.center.lng),
                    latitudinalMeters: req.spanMeters,
                    longitudinalMeters: req.spanMeters
                )
                map.setRegion(region, animated: true)
            }
            rebuildScene(map: map)
            syncHandle(map: map)
        }

        private func rebuildScene(map: MKMapView) {
            let scene = model.mapScene
            guard scene != lastScene, !draggingAnnotation else { return }
            lastScene = scene

            map.removeOverlays(sceneOverlays)
            map.removeAnnotations(sceneAnnotations)
            sceneOverlays = []
            sceneAnnotations = []

            func addPolygon(_ ring: [LatLng], title: String) {
                var coords = ring.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
                let poly = MKPolygon(coordinates: &coords, count: coords.count)
                poly.title = title
                sceneOverlays.append(poly)
            }
            func addPolyline(_ pts: [LatLng], title: String) {
                var coords = pts.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
                let line = MKPolyline(coordinates: &coords, count: coords.count)
                line.title = title
                sceneOverlays.append(line)
            }

            if let params = scene.sitePlan, let image = model.sitePlanImage {
                sceneOverlays.append(SitePlanOverlay(params: params, image: image))
            }
            if let ring = scene.poolRing { addPolygon(ring, title: "pool") }
            func addVertices(_ ring: [LatLng], kind: VertexAnnotation.Kind, polygonIndex: Int) {
                guard !scene.cleanView else { return }
                for (i, p) in ring.enumerated() {
                    sceneAnnotations.append(VertexAnnotation(
                        kind: kind, polygonIndex: polygonIndex, vertexIndex: i,
                        coordinate: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng)))
                }
            }

            if scene.lot.count >= 3 {
                addPolygon(scene.lot, title: scene.lotViolating ? "lotViol" : "lot")
                addVertices(scene.lot, kind: .lot, polygonIndex: 0)
            }
            for (si, s) in scene.structures.enumerated() where s.count >= 3 {
                let viol = scene.structureViolating.indices.contains(si) && scene.structureViolating[si]
                addPolygon(s, title: viol ? "structViol" : "struct")
                addVertices(s, kind: .structure, polygonIndex: si)
            }
            for (zi, z) in scene.zones.enumerated() where z.points.count >= 3 {
                let viol = scene.zoneViolating.indices.contains(zi) && scene.zoneViolating[zi]
                addPolygon(z.points, title: viol ? "zoneViol" : "zone")
                addVertices(z.points, kind: .zone, polygonIndex: zi)
            }
            if scene.drawing, !scene.draft.isEmpty {
                if scene.draft.count > 1 { addPolyline(scene.draft, title: "draft") }
                for p in scene.draft {
                    sceneAnnotations.append(DraftDotAnnotation(
                        coordinate: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng)))
                }
            }
            let formatter = UnitFormatter(system: scene.displayUnits)
            for c in scene.connectors {
                let title: String
                if c.violating {
                    title = "connViol"
                } else {
                    switch c.kind {
                    case .lot, .equipmentToLot: title = "connLot"
                    case .structure: title = "connStruct"
                    case .equipmentToPool: title = "connEquip"
                    case .zone: title = "connZone"
                    }
                }
                addPolyline([c.from, c.to], title: title)
                let mid = CLLocationCoordinate2D(
                    latitude: (c.from.lat + c.to.lat) / 2,
                    longitude: (c.from.lng + c.to.lng) / 2
                )
                sceneAnnotations.append(DistanceLabelAnnotation(
                    coordinate: mid,
                    text: formatter.distance(c.distM),
                    violating: c.violating,
                    kind: c.kind
                ))
            }
            for pin in scene.pins {
                sceneAnnotations.append(PinAnnotation(pin: pin))
            }
            if scene.measurePoints.count > 1 {
                addPolyline(scene.measurePoints, title: "measure")
            }
            for (i, p) in scene.measurePoints.enumerated() {
                sceneAnnotations.append(MeasureDotAnnotation(
                    coordinate: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng),
                    snapped: scene.measureSnapped.indices.contains(i) && scene.measureSnapped[i]
                ))
            }

            map.addOverlays(sceneOverlays)
            map.addAnnotations(sceneAnnotations)
        }

        private var tileOverlay: MKTileOverlay?
        private var tileTemplate: String?

        private func syncTileOverlay(map: MKMapView) {
            let template = model.customTileTemplate?.trimmingCharacters(in: .whitespaces)
            let normalized = (template?.isEmpty ?? true) ? nil : template
            guard normalized != tileTemplate else { return }
            tileTemplate = normalized
            if let tileOverlay {
                map.removeOverlay(tileOverlay)
                self.tileOverlay = nil
            }
            if let normalized {
                let overlay = MKTileOverlay(urlTemplate: normalized)
                overlay.canReplaceMapContent = true
                map.insertOverlay(overlay, at: 0, level: .aboveRoads)
                tileOverlay = overlay
            }
        }

        private func syncHandle(map: MKMapView) {
            guard let center = model.poolCenter, !model.cleanView else {
                if handleOnMap {
                    map.removeAnnotation(handleAnnotation)
                    handleOnMap = false
                }
                return
            }
            if !draggingAnnotation {
                handleAnnotation.coordinate = CLLocationCoordinate2D(latitude: center.lat, longitude: center.lng)
            }
            if !handleOnMap {
                map.addAnnotation(handleAnnotation)
                handleOnMap = true
            }
        }

        // MARK: annotation views

        nonisolated func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            return MainActor.assumeIsolated {
                switch annotation {
                case let v as VertexAnnotation:
                    return Self.vertexView(for: v, on: mapView)
                case let d as DraftDotAnnotation:
                    return Self.draftDotView(for: d, on: mapView)
                case let l as DistanceLabelAnnotation:
                    return Self.distanceLabelView(for: l, on: mapView)
                case let p as PinAnnotation:
                    return Self.pinView(for: p, on: mapView)
                case let m as MeasureDotAnnotation:
                    return Self.measureDotView(for: m, on: mapView)
                case is MKPointAnnotation:
                    return Self.poolHandleView(for: annotation, on: mapView)
                default:
                    return nil
                }
            }
        }

        private static func dequeue(_ id: String, for annotation: MKAnnotation, on map: MKMapView) -> MKAnnotationView {
            let view = map.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.canShowCallout = false
            return view
        }

        private static func circleImage(diameter: CGFloat, pad: CGFloat, fill: UIColor, core: UIColor?) -> UIImage {
            let side = diameter + pad * 2
            return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
                let c = ctx.cgContext
                c.setFillColor(fill.cgColor)
                c.fillEllipse(in: CGRect(x: pad, y: pad, width: diameter, height: diameter))
                if let core {
                    let inset = diameter * 0.32
                    c.setFillColor(core.cgColor)
                    c.fillEllipse(in: CGRect(x: pad + inset, y: pad + inset,
                                             width: diameter - inset * 2, height: diameter - inset * 2))
                }
            }
        }

        private static func poolHandleView(for annotation: MKAnnotation, on map: MKMapView) -> MKAnnotationView {
            let view = dequeue("poolHandle", for: annotation, on: map)
            view.isDraggable = true
            // 44 pt touch target with a 20 pt visible handle.
            view.image = circleImage(diameter: 20, pad: 12, fill: UIColor(white: 1, alpha: 0.9), core: Palette.poolStroke)
            return view
        }

        private static func vertexView(for annotation: VertexAnnotation, on map: MKMapView) -> MKAnnotationView {
            let id: String
            let color: UIColor
            switch annotation.kind {
            case .lot: id = "lotVertex"; color = Palette.lot
            case .structure: id = "structVertex"; color = Palette.structFill
            case .zone: id = "zoneVertex"; color = Palette.zone
            }
            let view = dequeue(id, for: annotation, on: map)
            view.isDraggable = true
            view.image = circleImage(diameter: 14, pad: 15, fill: .white, core: color)
            return view
        }

        private static func draftDotView(for annotation: DraftDotAnnotation, on map: MKMapView) -> MKAnnotationView {
            let view = dequeue("draftDot", for: annotation, on: map)
            view.isDraggable = false
            view.image = circleImage(diameter: 12, pad: 2, fill: .white, core: Palette.lot)
            return view
        }

        private static func pinView(for annotation: PinAnnotation, on map: MKMapView) -> MKAnnotationView {
            let view = dequeue("pin-\(annotation.kind.rawValue)", for: annotation, on: map)
            view.isDraggable = true
            let color = annotation.kind.measured ? Palette.ink : Palette.snap
            let side: CGFloat = 44 // touch target; visible badge is 28 pt
            view.image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
                let c = ctx.cgContext
                let badge = CGRect(x: 8, y: 8, width: 28, height: 28)
                c.setFillColor(color.withAlphaComponent(0.95).cgColor)
                c.fillEllipse(in: badge)
                c.setStrokeColor(UIColor.white.cgColor)
                c.setLineWidth(2)
                c.strokeEllipse(in: badge)
                let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
                if let symbol = UIImage(systemName: annotation.kind.symbolName, withConfiguration: config)?
                    .withTintColor(.white, renderingMode: .alwaysOriginal) {
                    let s = symbol.size
                    symbol.draw(at: CGPoint(x: badge.midX - s.width / 2, y: badge.midY - s.height / 2))
                }
            }
            return view
        }

        private static func measureDotView(for annotation: MeasureDotAnnotation, on map: MKMapView) -> MKAnnotationView {
            let view = dequeue(annotation.snapped ? "measureSnap" : "measureDot", for: annotation, on: map)
            view.isDraggable = false
            view.isEnabled = false
            view.image = circleImage(
                diameter: annotation.snapped ? 14 : 12, pad: 2,
                fill: .white,
                core: annotation.snapped ? Palette.snap : Palette.ink
            )
            return view
        }

        private static func distanceLabelView(for annotation: DistanceLabelAnnotation, on map: MKMapView) -> MKAnnotationView {
            let view = dequeue("distLabel", for: annotation, on: map)
            view.isDraggable = false
            view.isEnabled = false
            let text = annotation.text as NSString
            let font = UIFont.systemFont(ofSize: 12, weight: .semibold)
            let padH: CGFloat = 6, padV: CGFloat = 3
            let textSize = text.size(withAttributes: [.font: font])
            let size = CGSize(width: ceil(textSize.width) + padH * 2, height: ceil(textSize.height) + padV * 2)
            let bg: UIColor
            if annotation.violating {
                bg = Palette.warn
            } else {
                switch annotation.kind {
                case .lot, .equipmentToLot: bg = Palette.lot
                case .structure: bg = Palette.structStroke
                case .equipmentToPool: bg = Palette.ink
                case .zone: bg = Palette.zone
                }
            }
            view.image = UIGraphicsImageRenderer(size: size).image { ctx in
                let rect = CGRect(origin: .zero, size: size)
                let path = UIBezierPath(roundedRect: rect, cornerRadius: size.height / 2)
                bg.withAlphaComponent(0.92).setFill()
                path.fill()
                text.draw(
                    at: CGPoint(x: padH, y: padV),
                    withAttributes: [.font: font, .foregroundColor: UIColor.white]
                )
            }
            return view
        }

        // MARK: dragging

        nonisolated func mapView(
            _ mapView: MKMapView,
            annotationView view: MKAnnotationView,
            didChange newState: MKAnnotationView.DragState,
            fromOldState oldState: MKAnnotationView.DragState
        ) {
            MainActor.assumeIsolated {
                switch newState {
                case .starting, .dragging:
                    draggingAnnotation = true
                case .ending, .canceling, .none:
                    let wasDragging = draggingAnnotation
                    draggingAnnotation = false
                    view.dragState = .none
                    guard wasDragging, let annotation = view.annotation else { return }
                    let coord = annotation.coordinate
                    let p = LatLng(lat: coord.latitude, lng: coord.longitude)
                    if let vertex = annotation as? VertexAnnotation {
                        model.moveVertex(
                            kind: vertex.kind,
                            polygonIndex: vertex.polygonIndex,
                            vertexIndex: vertex.vertexIndex,
                            to: p
                        )
                    } else if let pin = annotation as? PinAnnotation {
                        model.movePin(id: pin.pinID, to: p)
                    } else if annotation === handleAnnotation {
                        model.setPoolCenter(p)
                    }
                default:
                    break
                }
            }
        }

        // MARK: overlay renderers

        nonisolated func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let region = mapView.region
            MainActor.assumeIsolated {
                model.visibleRegion = region
            }
        }

        nonisolated func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tile)
            }
            if let sitePlan = overlay as? SitePlanOverlay {
                return SitePlanRenderer(overlay: sitePlan)
            }
            if let poly = overlay as? MKPolygon {
                let r = MKPolygonRenderer(polygon: poly)
                r.lineWidth = 2
                switch poly.title {
                case "pool":
                    r.fillColor = Palette.poolFill
                    r.strokeColor = Palette.poolStroke
                case "lot":
                    r.strokeColor = Palette.lot
                    r.fillColor = Palette.lot.withAlphaComponent(0.05)
                case "lotViol":
                    r.strokeColor = Palette.warn
                    r.fillColor = Palette.warn.withAlphaComponent(0.05)
                case "struct":
                    r.strokeColor = Palette.structStroke
                    r.fillColor = Palette.structFill.withAlphaComponent(0.15)
                case "structViol":
                    r.strokeColor = Palette.warn
                    r.fillColor = Palette.warn.withAlphaComponent(0.15)
                case "zone":
                    r.strokeColor = Palette.zone
                    r.fillColor = Palette.zone.withAlphaComponent(0.12)
                case "zoneViol":
                    r.strokeColor = Palette.warn
                    r.fillColor = Palette.warn.withAlphaComponent(0.12)
                default:
                    r.strokeColor = .white
                }
                return r
            }
            if let line = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.lineWidth = 2
                switch line.title {
                case "draft":
                    r.strokeColor = Palette.lot
                    r.lineDashPattern = [4, 4]
                case "connLot":
                    r.strokeColor = Palette.lot
                    r.lineDashPattern = [6, 4]
                case "connViol":
                    r.strokeColor = Palette.warn
                    r.lineDashPattern = [6, 4]
                case "connStruct":
                    r.strokeColor = Palette.structStroke
                    r.lineDashPattern = [6, 4]
                case "connEquip":
                    r.strokeColor = Palette.ink
                    r.lineDashPattern = [6, 4]
                case "connZone":
                    r.strokeColor = Palette.zone
                    r.lineDashPattern = [6, 4]
                case "measure":
                    r.strokeColor = Palette.measure
                    r.lineWidth = 3
                    r.lineDashPattern = [2, 6]
                default:
                    r.strokeColor = .white
                }
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
