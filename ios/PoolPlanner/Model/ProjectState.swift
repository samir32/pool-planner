import Foundation

/// Pin kinds, ported from the web app's ANNOT table. Equipment pins are
/// measured against the rule profile; safety pins are labels the user places
/// to document their compliance story (barrier rules differ everywhere).
enum PinKind: String, Codable, CaseIterable, Identifiable {
    // equipment (measured)
    case equipmentSet
    case heatPump
    case pump
    case filter
    // safety (labels only)
    case ladder
    case gate
    case selfClosingGate
    case doorAlarm
    case fenceOpening

    var id: String { rawValue }

    var measured: Bool {
        switch self {
        case .equipmentSet, .heatPump, .pump, .filter: return true
        default: return false
        }
    }

    var label: String {
        switch self {
        case .equipmentSet: return "Equipment set"
        case .heatPump: return "Heat pump"
        case .pump: return "Pump"
        case .filter: return "Filter"
        case .ladder: return "Ladder"
        case .gate: return "Gate"
        case .selfClosingGate: return "Self-closing gate"
        case .doorAlarm: return "Door alarm"
        case .fenceOpening: return "Fence opening"
        }
    }

    var symbolName: String {
        switch self {
        case .equipmentSet: return "gearshape.2"
        case .heatPump: return "fan"
        case .pump: return "wind"
        case .filter: return "line.3.horizontal.decrease.circle"
        case .ladder: return "figure.stairs"
        case .gate: return "door.left.hand.open"
        case .selfClosingGate: return "door.sliding.left.hand.closed"
        case .doorAlarm: return "bell"
        case .fenceOpening: return "rectangle.portrait.slash"
        }
    }
}

struct PlacedPin: Codable, Equatable, Identifiable {
    var id = UUID()
    var kind: PinKind
    var position: LatLng
}

/// A saved pool configuration (the web app's scenarios): shape, size,
/// rotation, position, and the rules in force when it was saved.
struct Scenario: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var shape: PoolShapeKind
    var widthFt: Double
    var lengthFt: Double
    var rotationDeg: Double
    var center: LatLng?
    var rules: RuleProfile
}

/// Georeferencing parameters for an imported site plan / survey image.
/// The image itself is stored as a separate file next to project.json.
struct SitePlanParams: Codable, Equatable {
    var center: LatLng
    /// Real-world width of the image on the ground, meters.
    var widthM: Double = 30
    var rotationDeg: Double = 0
    var opacity: Double = 0.7
    var whiteBacking = true
}

/// Everything worth restoring between launches — replaces the web app's
/// localStorage. (SwiftData can supersede this store later without touching
/// the model layer; the app plan's Phase 6 iCloud sync would ride on that.)
struct ProjectState: Codable, Equatable {
    var poolCenter: LatLng?
    var shape: PoolShapeKind = .oval
    var widthFt: Double = 15
    var lengthFt: Double = 30
    var rotationDeg: Double = 0
    var units: UnitSystem = .mixed
    var lot: [LatLng] = []
    var structures: [[LatLng]] = []
    var pins: [PlacedPin] = []
    var rules: RuleProfile = .example
    var scenarios: [Scenario] = []
    var sitePlan: SitePlanParams?
}

/// Loads/saves the project as JSON in the app's Documents directory.
struct ProjectStore {
    let url: URL

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("project.json")
    }

    func load() -> ProjectState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ProjectState.self, from: data)
    }

    func save(_ state: ProjectState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// The site plan image lives beside project.json as PNG data.
    var sitePlanImageURL: URL {
        url.deletingLastPathComponent().appendingPathComponent("siteplan.png")
    }

    func loadSitePlanImage() -> Data? {
        try? Data(contentsOf: sitePlanImageURL)
    }

    func saveSitePlanImage(_ data: Data?) {
        if let data {
            try? data.write(to: sitePlanImageURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: sitePlanImageURL)
        }
    }
}
