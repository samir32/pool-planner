import Foundation
import CoreLocation
import Combine
import MapKit

/// A named pool preset (dimensions in feet, matching retail sizing).
struct PoolPreset: Identifiable {
    let id = UUID()
    let name: String
    let shape: PoolShapeKind
    let widthFt: Double
    let lengthFt: Double

    static let aboveGround: [PoolPreset] = [
        PoolPreset(name: "12 ft round", shape: .round, widthFt: 12, lengthFt: 12),
        PoolPreset(name: "15 ft round", shape: .round, widthFt: 15, lengthFt: 15),
        PoolPreset(name: "18 ft round", shape: .round, widthFt: 18, lengthFt: 18),
        PoolPreset(name: "21 ft round", shape: .round, widthFt: 21, lengthFt: 21),
        PoolPreset(name: "12 × 24 ft oval", shape: .oval, widthFt: 12, lengthFt: 24),
        PoolPreset(name: "15 × 30 ft oval", shape: .oval, widthFt: 15, lengthFt: 30),
        PoolPreset(name: "18 × 33 ft oval", shape: .oval, widthFt: 18, lengthFt: 33),
    ]
    static let inground: [PoolPreset] = [
        PoolPreset(name: "12 × 24 ft rectangle", shape: .rect, widthFt: 12, lengthFt: 24),
        PoolPreset(name: "16 × 32 ft rectangle", shape: .rect, widthFt: 16, lengthFt: 32),
        PoolPreset(name: "18 × 36 ft rectangle", shape: .rect, widthFt: 18, lengthFt: 36),
        PoolPreset(name: "20 × 40 ft rectangle", shape: .rect, widthFt: 20, lengthFt: 40),
    ]
}

@MainActor
final class PlannerModel: NSObject, ObservableObject {
    struct CameraRequest: Equatable {
        var center: LatLng
        var spanMeters: Double
        var id = UUID()
    }

    enum DrawMode: Equatable {
        case none
        case lot
        case structure
    }

    @Published var poolCenter: LatLng?
    @Published var shape: PoolShapeKind = .oval {
        didSet { if shape == .round { lengthFt = widthFt } }
    }
    @Published var widthFt: Double = 15 {
        didSet { if shape == .round, lengthFt != widthFt { lengthFt = widthFt } }
    }
    @Published var lengthFt: Double = 30
    /// 0–180° like the web app (shapes are symmetric).
    @Published var rotationDeg: Double = 0
    @Published var units: UnitSystem = .mixed
    @Published var searchText = ""
    @Published var searchError: String?
    @Published var isSearching = false
    @Published var cameraRequest: CameraRequest?
    /// Bumped by the sidebar button; the map coordinator answers by placing
    /// the pool at the visible map center.
    @Published var placeAtCenterToken: UUID?

    // Phase 3: drawn geometry + rules
    @Published var drawMode: DrawMode = .none
    @Published var draftPoints: [LatLng] = []
    @Published var lot: [LatLng] = []
    @Published var structures: [[LatLng]] = []
    @Published var rules: RuleProfile = .example

    // Phase 4: pins, measure, scenarios
    @Published var pins: [PlacedPin] = []
    @Published var measureMode = false
    @Published var measurePoints: [LatLng] = []
    @Published var measureSnapped: [Bool] = []
    @Published var scenarios: [Scenario] = []

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var tookFirstFix = false
    private let store: ProjectStore
    private var saveCancellable: AnyCancellable?

    init(store: ProjectStore = ProjectStore()) {
        self.store = store
        super.init()
        if let saved = store.load() {
            apply(state: saved)
            if let center = poolCenter {
                cameraRequest = CameraRequest(center: center, spanMeters: 150)
                tookFirstFix = true // don't yank the camera to the user's location
            }
        }
        // Autosave: debounce any model change, then snapshot and write.
        saveCancellable = objectWillChange
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.store.save(self.projectState)
            }
    }

    var projectState: ProjectState {
        ProjectState(
            poolCenter: poolCenter, shape: shape, widthFt: widthFt, lengthFt: lengthFt,
            rotationDeg: rotationDeg, units: units, lot: lot, structures: structures,
            pins: pins, rules: rules, scenarios: scenarios
        )
    }

    private func apply(state: ProjectState) {
        poolCenter = state.poolCenter
        shape = state.shape
        widthFt = state.widthFt
        lengthFt = state.lengthFt
        rotationDeg = state.rotationDeg
        units = state.units
        lot = state.lot
        structures = state.structures
        pins = state.pins
        rules = state.rules
        scenarios = state.scenarios
    }

    var formatter: UnitFormatter { UnitFormatter(system: units) }

    /// Semi-axes in meters: half-length along the rotated x-axis, half-width
    /// along y — the web app's convention.
    var semiAxes: (aM: Double, bM: Double) {
        (lengthFt * Geo.metersPerFoot / 2, widthFt * Geo.metersPerFoot / 2)
    }

    var poolRing: [LatLng]? {
        guard let c = poolCenter else { return nil }
        let ax = semiAxes
        return PoolShape.points(center: c, aM: ax.aM, bM: ax.bM, rotDeg: rotationDeg, shape: shape)
    }

    var footprintM2: Double {
        let ax = semiAxes
        return PoolShape.footprintM2(aM: ax.aM, bM: ax.bM, shape: shape)
    }

    func placePoolAtMapCenter() {
        placeAtCenterToken = UUID()
    }

    // MARK: - Compliance

    var report: ComplianceReport? {
        guard let center = poolCenter, let ring = poolRing else { return nil }
        let site = SiteGeometry(
            poolCenter: center,
            poolRing: ring,
            poolFootprintM2: footprintM2,
            lot: lot.count >= 3 ? lot : nil,
            structures: structures,
            equipment: measuredPins.map(\.position)
        )
        return ComplianceEngine.evaluate(site: site, rules: rules)
    }

    /// Pins the compliance engine measures (equipment kinds only), in a stable
    /// order so report indices line up.
    var measuredPins: [PlacedPin] { pins.filter { $0.kind.measured } }

    /// Move the whole pool so the given lot connector equals the typed
    /// distance (the web app's nudgePoolLot).
    func nudgePool(along gap: EdgeGap, ref: LatLng, target: Double) {
        guard target >= 0 else { return }
        let c = gap.connector
        let dx = c.from.x - c.to.x, dy = c.from.y - c.to.y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 0 else { return }
        let t = target - len
        poolCenter = Geo.xyToLL(XY(x: t * dx / len, y: t * dy / len), ref: ref)
    }

    // MARK: - Drawing lot & structures

    func beginDraw(_ mode: DrawMode) {
        drawMode = mode
        draftPoints = []
    }

    func addDraftPoint(_ p: LatLng) {
        if let last = draftPoints.last {
            // ignore accidental duplicate taps (< 0.5 m apart), like the web app
            let d = Geo.llToXY(p, ref: last)
            if (d.x * d.x + d.y * d.y).squareRoot() < 0.5 { return }
        }
        draftPoints.append(p)
    }

    func finishDraw() {
        if draftPoints.count >= 3 {
            switch drawMode {
            case .lot: lot = draftPoints
            case .structure: structures.append(draftPoints)
            case .none: break
            }
        }
        drawMode = .none
        draftPoints = []
    }

    func cancelDraw() {
        drawMode = .none
        draftPoints = []
    }

    func clearLot() { lot = [] }

    func removeLastStructure() {
        if !structures.isEmpty { structures.removeLast() }
    }

    // MARK: - Pins

    /// Set by the sidebar menu; the map coordinator places the pin at the
    /// visible map center and clears it.
    @Published var pendingPinKind: PinKind?

    func requestPin(_ kind: PinKind) {
        pendingPinKind = kind
    }

    func addPin(_ kind: PinKind, at p: LatLng) {
        pins.append(PlacedPin(kind: kind, position: p))
    }

    func movePin(id: UUID, to p: LatLng) {
        guard let i = pins.firstIndex(where: { $0.id == id }) else { return }
        pins[i].position = p
    }

    func removePin(id: UUID) {
        pins.removeAll { $0.id == id }
    }

    // MARK: - Measure

    func toggleMeasure() {
        measureMode.toggle()
        if measureMode { drawMode = .none } else { clearMeasure() }
    }

    func addMeasurePoint(_ p: LatLng, snapped: Bool) {
        measurePoints.append(p)
        measureSnapped.append(snapped)
    }

    func clearMeasure() {
        measurePoints = []
        measureSnapped = []
    }

    /// (last segment, running total) in meters, geodesic like the web app.
    var measureDistances: (last: Double, total: Double)? {
        guard measurePoints.count > 1 else { return nil }
        func d(_ a: LatLng, _ b: LatLng) -> Double {
            CLLocation(latitude: a.lat, longitude: a.lng)
                .distance(from: CLLocation(latitude: b.lat, longitude: b.lng))
        }
        var total = 0.0
        for i in 1..<measurePoints.count { total += d(measurePoints[i - 1], measurePoints[i]) }
        let last = d(measurePoints[measurePoints.count - 2], measurePoints[measurePoints.count - 1])
        return (last, total)
    }

    // MARK: - Scenarios

    func saveScenario(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let scenario = Scenario(
            name: trimmed, shape: shape, widthFt: widthFt, lengthFt: lengthFt,
            rotationDeg: rotationDeg, center: poolCenter, rules: rules
        )
        // Replace an existing scenario with the same name, like the web app.
        if let i = scenarios.firstIndex(where: { $0.name == trimmed }) {
            scenarios[i] = scenario
        } else {
            scenarios.append(scenario)
        }
    }

    func loadScenario(_ scenario: Scenario) {
        shape = scenario.shape
        widthFt = scenario.widthFt
        lengthFt = scenario.lengthFt
        rotationDeg = scenario.rotationDeg
        rules = scenario.rules
        if let center = scenario.center {
            poolCenter = center
            cameraRequest = CameraRequest(center: center, spanMeters: 150)
        }
    }

    func removeScenario(id: UUID) {
        scenarios.removeAll { $0.id == id }
    }

    func moveVertex(kind: VertexAnnotation.Kind, polygonIndex: Int, vertexIndex: Int, to p: LatLng) {
        switch kind {
        case .lot:
            guard lot.indices.contains(vertexIndex) else { return }
            lot[vertexIndex] = p
        case .structure:
            guard structures.indices.contains(polygonIndex),
                  structures[polygonIndex].indices.contains(vertexIndex) else { return }
            structures[polygonIndex][vertexIndex] = p
        }
    }

    func apply(_ preset: PoolPreset) {
        shape = preset.shape
        widthFt = preset.widthFt
        lengthFt = preset.lengthFt
    }

    /// Fold any gesture angle into the 0–180° slider range.
    static func normalizeRotation(_ deg: Double) -> Double {
        let m = deg.truncatingRemainder(dividingBy: 180)
        return m < 0 ? m + 180 : m
    }

    // MARK: - Location

    func start() {
        locationManager.delegate = self
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        default:
            break
        }
    }

    // MARK: - Address search

    func search() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        isSearching = true
        searchError = nil
        geocoder.geocodeAddressString(query) { [weak self] placemarks, error in
            Task { @MainActor in
                guard let self else { return }
                self.isSearching = false
                if let loc = placemarks?.first?.location {
                    self.cameraRequest = CameraRequest(
                        center: LatLng(lat: loc.coordinate.latitude, lng: loc.coordinate.longitude),
                        spanMeters: 150
                    )
                } else {
                    self.searchError = error == nil ? "Address not found" : "Address lookup failed"
                }
            }
        }
    }
}

extension PlannerModel: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.locationManager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            guard !self.tookFirstFix else { return }
            self.tookFirstFix = true
            self.cameraRequest = CameraRequest(
                center: LatLng(lat: loc.coordinate.latitude, lng: loc.coordinate.longitude),
                spanMeters: 200
            )
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // No location — the map keeps its default region; search still works.
    }
}
