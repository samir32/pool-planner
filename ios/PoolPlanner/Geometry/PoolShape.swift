import Foundation

/// The pool shapes offered by the app. Raw values are persisted, so existing
/// projects keep decoding as new cases are added.
///
/// Vocabulary follows the inground-pool industry: rectangle, Roman (straight
/// sides with rounded ends), Grecian (rectangle with truncated corners),
/// kidney, lazy L (angled offset) and true L (square offset), figure 8.
public enum PoolShapeKind: String, Codable, CaseIterable, Sendable {
    case oval
    case round
    case rect
    case roman
    case grecian
    case kidney
    case lazyL
    case trueL
    case figure8

    public var isAboveGroundStyle: Bool {
        self == .oval || self == .round
    }

    /// Round pools are defined by a single diameter.
    public var isSymmetric: Bool { self == .round }
}

public enum PoolShape {
    /// Ring of lat/lng points for a pool at `center`.
    /// `aM`/`bM` are semi-axes in meters: half-length along the rotated x-axis,
    /// half-width along y — same convention as the web app's redraw().
    ///
    /// Rect and the ellipses reproduce the web app's math exactly (the parity
    /// fixtures pin them); the other shapes are sampled from normalized
    /// outlines scaled by the same semi-axes.
    public static func points(
        center: LatLng, aM: Double, bM: Double, rotDeg: Double, shape: PoolShapeKind
    ) -> [LatLng] {
        let th = rotDeg * .pi / 180
        let cosT = cos(th), sinT = sin(th)

        func place(_ x: Double, _ y: Double) -> LatLng {
            Geo.offset(center, dx: x * cosT - y * sinT, dy: x * sinT + y * cosT)
        }

        switch shape {
        case .rect:
            return [(-aM, -bM), (aM, -bM), (aM, bM), (-aM, bM)].map { place($0.0, $0.1) }
        case .oval, .round:
            let n = 72
            return (0..<n).map { i in
                let t = (Double(i) / Double(n)) * 2 * .pi
                return place(aM * cos(t), bM * sin(t))
            }
        default:
            return normalizedOutline(shape).map { place($0.x * aM, $0.y * bM) }
        }
    }

    /// Water-surface footprint in m².
    public static func footprintM2(aM: Double, bM: Double, shape: PoolShapeKind) -> Double {
        switch shape {
        case .rect:
            return (2 * aM) * (2 * bM)
        case .oval, .round:
            return .pi * aM * bM
        default:
            // shoelace over the scaled outline
            let pts = normalizedOutline(shape).map { (x: $0.x * aM, y: $0.y * bM) }
            var a = 0.0
            var j = pts.count - 1
            for i in 0..<pts.count {
                a += (pts[j].x + pts[i].x) * (pts[j].y - pts[i].y)
                j = i
            }
            return abs(a / 2)
        }
    }

    // MARK: - Normalized outlines
    //
    // Unit space: x spans [-1, 1] along the length, y spans [-1, 1] across the
    // width, so scaling by the semi-axes gives the requested envelope.

    public static func normalizedOutline(_ shape: PoolShapeKind) -> [XY] {
        switch shape {
        case .rect:
            return [XY(x: -1, y: -1), XY(x: 1, y: -1), XY(x: 1, y: 1), XY(x: -1, y: 1)]
        case .oval, .round:
            return (0..<72).map { i in
                let t = (Double(i) / 72) * 2 * .pi
                return XY(x: cos(t), y: sin(t))
            }
        case .roman:
            // straight sides, semicircular ends
            let capX = 0.62, n = 24
            var pts: [XY] = []
            for i in 0...n { // right cap, -90°..90°
                let t = -Double.pi / 2 + Double(i) / Double(n) * .pi
                pts.append(XY(x: capX + (1 - capX) * cos(t), y: sin(t)))
            }
            for i in 0...n { // left cap, 90°..270°
                let t = Double.pi / 2 + Double(i) / Double(n) * .pi
                pts.append(XY(x: -capX + (1 - capX) * cos(t), y: sin(t)))
            }
            return pts
        case .grecian:
            // rectangle with truncated corners
            let c = 0.28
            return [
                XY(x: -1 + c, y: -1), XY(x: 1 - c, y: -1),
                XY(x: 1, y: -1 + c), XY(x: 1, y: 1 - c),
                XY(x: 1 - c, y: 1), XY(x: -1 + c, y: 1),
                XY(x: -1, y: 1 - c), XY(x: -1, y: -1 + c),
            ]
        case .kidney:
            return waistedEllipse(depth: 0.42, spread: 0.42, bothSides: false)
        case .figure8:
            return waistedEllipse(depth: 0.5, spread: 0.3, bothSides: true)
        case .lazyL:
            // rectangle with an angled offset wing
            return [
                XY(x: -1, y: -1), XY(x: 0.28, y: -1), XY(x: 0.5, y: 0.18),
                XY(x: 1, y: 0.18), XY(x: 1, y: 1), XY(x: -1, y: 1),
            ]
        case .trueL:
            return [
                XY(x: -1, y: -1), XY(x: 0.3, y: -1), XY(x: 0.3, y: 0.18),
                XY(x: 1, y: 0.18), XY(x: 1, y: 1), XY(x: -1, y: 1),
            ]
        }
    }

    /// An ellipse pinched inward near x = 0 — one side gives a kidney, both
    /// sides give a figure 8. Rescaled so the outline still fills y ∈ [-1, 1].
    private static func waistedEllipse(depth: Double, spread: Double, bothSides: Bool) -> [XY] {
        let n = 96
        var pts: [XY] = []
        for i in 0..<n {
            let t = (Double(i) / Double(n)) * 2 * .pi
            let x = cos(t)
            var y = sin(t)
            let pinch = depth * exp(-(x * x) / (spread * spread))
            if bothSides || y > 0 {
                y *= (1 - pinch)
            }
            pts.append(XY(x: x, y: y))
        }
        // renormalize the width so the shape still spans the requested envelope
        let maxY = pts.map { abs($0.y) }.max() ?? 1
        guard maxY > 0 else { return pts }
        return pts.map { XY(x: $0.x, y: $0.y / maxY) }
    }
}
