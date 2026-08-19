import Foundation

public enum PoolShapeKind: String, Codable, CaseIterable, Sendable {
    case oval
    case round
    case rect
}

public enum PoolShape {
    /// Ring of lat/lng points for a pool at `center`.
    /// `aM`/`bM` are semi-axes in meters: half-length along the rotated x-axis,
    /// half-width along y — same convention as the web app's redraw().
    /// Rect yields 4 corners; oval/round a 72-point ring.
    public static func points(
        center: LatLng, aM: Double, bM: Double, rotDeg: Double, shape: PoolShapeKind
    ) -> [LatLng] {
        let th = rotDeg * .pi / 180
        let cosT = cos(th), sinT = sin(th)
        var pts: [LatLng] = []
        if shape == .rect {
            let corners = [(-aM, -bM), (aM, -bM), (aM, bM), (-aM, bM)]
            for (x, y) in corners {
                pts.append(Geo.offset(center, dx: x * cosT - y * sinT, dy: x * sinT + y * cosT))
            }
        } else {
            let n = 72
            for i in 0..<n {
                let t = (Double(i) / Double(n)) * 2 * .pi
                let x = aM * cos(t), y = bM * sin(t)
                pts.append(Geo.offset(center, dx: x * cosT - y * sinT, dy: x * sinT + y * cosT))
            }
        }
        return pts
    }

    /// Water-surface footprint in m² from the semi-axes.
    public static func footprintM2(aM: Double, bM: Double, shape: PoolShapeKind) -> Double {
        shape == .rect ? (2 * aM) * (2 * bM) : .pi * aM * bM
    }
}
