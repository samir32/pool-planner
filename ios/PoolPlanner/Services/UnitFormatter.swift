import Foundation

public enum UnitSystem: String, Codable, CaseIterable, Sendable {
    /// ft/in everywhere.
    case imperial
    /// meters everywhere.
    case metric
    /// The web app's convention (common in Canada): pool dimensions in feet,
    /// setbacks/distances in meters.
    case mixed
}

/// Single source of truth for turning internal meters into display strings.
/// Internal math is always meters; display units never leak into the model.
public struct UnitFormatter: Sendable {
    public var system: UnitSystem

    public init(system: UnitSystem) {
        self.system = system
    }

    /// Distances: setbacks, gaps, measure-tool readouts.
    /// Metric path matches the web's fmtM (nearest 5 cm, two decimals);
    /// imperial rounds to the nearest inch.
    public func distance(_ meters: Double) -> String {
        switch system {
        case .metric, .mixed:
            return Self.metricDistance(meters)
        case .imperial:
            return Self.imperialDistance(meters)
        }
    }

    /// Pool dimensions (width/length).
    public func poolDimension(_ meters: Double) -> String {
        switch system {
        case .metric:
            return Self.metricDistance(meters)
        case .imperial, .mixed:
            return Self.imperialDistance(meters)
        }
    }

    /// Areas (water surface, lot).
    public func area(_ squareMeters: Double) -> String {
        switch system {
        case .metric, .mixed:
            return String(format: "%.1f m²", squareMeters)
        case .imperial:
            let ft2 = squareMeters / (Geo.metersPerFoot * Geo.metersPerFoot)
            return "\(Int(ft2.rounded())) ft²"
        }
    }

    static func metricDistance(_ meters: Double) -> String {
        String(format: "%.2f m", Geo.round05(meters))
    }

    static func imperialDistance(_ meters: Double) -> String {
        let totalInches = Int((meters / 0.0254).rounded())
        let ft = totalInches / 12
        let inches = totalInches % 12
        if inches == 0 { return "\(ft) ft" }
        if ft == 0 { return "\(inches) in" }
        return "\(ft) ft \(inches) in"
    }
}
