import Foundation

// Port of the web app's geometry core (index.html). All math runs in a local
// flat-earth XY frame (meters) anchored at a reference coordinate, exactly as
// the web app does — parity is verified against fixtures generated from the
// original JavaScript (PoolPlannerTests/Fixtures/parity.json).

public struct LatLng: Codable, Equatable, Hashable, Sendable {
    public var lat: Double
    public var lng: Double
    public init(lat: Double, lng: Double) {
        self.lat = lat
        self.lng = lng
    }
}

public struct XY: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum Geo {
    public static let metersPerFoot = 0.3048
    /// Meters per degree of latitude — same constant the web app uses.
    static let metersPerDegree = 111_320.0

    /// Shift a coordinate by (dx, dy) meters (east, north).
    public static func offset(_ c: LatLng, dx: Double, dy: Double) -> LatLng {
        let dLat = dy / metersPerDegree
        let dLng = dx / (metersPerDegree * cos(c.lat * .pi / 180))
        return LatLng(lat: c.lat + dLat, lng: c.lng + dLng)
    }

    /// latlng -> local planar meters relative to a reference latlng.
    public static func llToXY(_ ll: LatLng, ref: LatLng) -> XY {
        let latRad = ref.lat * .pi / 180
        return XY(
            x: (ll.lng - ref.lng) * metersPerDegree * cos(latRad),
            y: (ll.lat - ref.lat) * metersPerDegree
        )
    }

    /// local planar meters -> latlng (inverse of llToXY).
    public static func xyToLL(_ pt: XY, ref: LatLng) -> LatLng {
        LatLng(
            lat: ref.lat + pt.y / metersPerDegree,
            lng: ref.lng + pt.x / (metersPerDegree * cos(ref.lat * .pi / 180))
        )
    }

    public static func distPointSeg(_ p: XY, _ a: XY, _ b: XY) -> Double {
        closestPtSeg(p, a, b).d
    }

    /// Closest point on segment a-b to point p; returns distance and point.
    public static func closestPtSeg(_ p: XY, _ a: XY, _ b: XY) -> (d: Double, c: XY) {
        let abx = b.x - a.x, aby = b.y - a.y
        let apx = p.x - a.x, apy = p.y - a.y
        let len2 = abx * abx + aby * aby
        var t = len2 != 0 ? (apx * abx + apy * aby) / len2 : 0
        t = max(0, min(1, t))
        let c = XY(x: a.x + t * abx, y: a.y + t * aby)
        let dx = p.x - c.x, dy = p.y - c.y
        return ((dx * dx + dy * dy).squareRoot(), c)
    }

    /// Ray-casting point-in-polygon, identical branch structure to the web app.
    public static func pointInPoly(_ pt: XY, _ poly: [XY]) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let xi = poly[i].x, yi = poly[i].y
            let xj = poly[j].x, yj = poly[j].y
            if (yi > pt.y) != (yj > pt.y),
               pt.x < (xj - xi) * (pt.y - yi) / (yj - yi) + xi {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// Shoelace area of a lat/lng ring, projected around its first vertex.
    public static func polygonAreaM2(_ ptsLL: [LatLng]) -> Double {
        guard ptsLL.count >= 3 else { return 0 }
        let ref = ptsLL[0]
        let xy = ptsLL.map { llToXY($0, ref: ref) }
        var a = 0.0
        var j = xy.count - 1
        for i in 0..<xy.count {
            a += (xy[j].x + xy[i].x) * (xy[j].y - xy[i].y)
            j = i
        }
        return abs(a / 2)
    }

    /// Nearest point on a closed polygon's boundary to p.
    public static func nearestOnPoly(_ p: XY, _ poly: [XY]) -> (d: Double, c: XY)? {
        guard !poly.isEmpty else { return nil }
        var best: (d: Double, c: XY)?
        for i in 0..<poly.count {
            let r = closestPtSeg(p, poly[i], poly[(i + 1) % poly.count])
            if best == nil || r.d < best!.d { best = r }
        }
        return best
    }

    /// Metric display rounding: nearest 5 cm (the web app's round05).
    public static func round05(_ x: Double) -> Double {
        (x / 0.05).rounded() * 0.05
    }
}
