import Foundation

/// Everything the engine measures against. All coordinates lat/lng; the engine
/// projects into a local XY frame anchored at the pool center, matching the
/// web app's refreshLotDistance / refreshStructDistance / refreshEquip.
public struct SiteGeometry: Sendable {
    public var poolCenter: LatLng
    public var poolRing: [LatLng]
    public var poolFootprintM2: Double
    public var lot: [LatLng]?
    public var structures: [[LatLng]]
    public var equipment: [LatLng]
    /// Extra restriction polygons, each with an optional own setback.
    public var zones: [(points: [LatLng], setbackM: Double?)]

    public init(
        poolCenter: LatLng, poolRing: [LatLng], poolFootprintM2: Double,
        lot: [LatLng]? = nil, structures: [[LatLng]] = [], equipment: [LatLng] = [],
        zones: [(points: [LatLng], setbackM: Double?)] = []
    ) {
        self.poolCenter = poolCenter
        self.poolRing = poolRing
        self.poolFootprintM2 = poolFootprintM2
        self.lot = lot
        self.structures = structures
        self.equipment = equipment
        self.zones = zones
    }
}

/// A shortest connector between the pool and something, in the report's
/// local XY frame (anchored at the pool center).
public struct Connector: Equatable, Sendable {
    public var d: Double
    public var from: XY
    public var to: XY
}

public struct EdgeGap: Equatable, Sendable {
    public var edgeIndex: Int
    public var connector: Connector
}

public struct EquipmentCheck: Equatable, Sendable {
    public var index: Int
    /// Distance to the nearest pool wall; nil rule → not evaluated.
    public var toPoolM: Double?
    public var poolViolation: Bool
    /// Distance to the nearest lot line (only when a lot is drawn).
    public var toLotM: Double?
    public var lotViolation: Bool
}

public struct ComplianceReport: Sendable {
    /// Local frame reference (the pool center) for converting connectors back.
    public var ref: LatLng
    /// Per-lot-edge shortest connectors, sorted nearest-first (web shows two).
    public var lotEdgeGaps: [EdgeGap]
    public var poolCenterInsideLot: Bool?
    public var lotSetbackViolation: Bool
    /// Shortest connector per structure, same order as input.
    public var structureGaps: [Connector?]
    public var structureSetbackViolation: Bool
    public var equipment: [EquipmentCheck]
    /// Shortest pool-to-zone connector per zone, same order as input.
    public var zoneGaps: [Connector?]
    /// Per zone: violated when the pool center sits inside it, or the gap is
    /// under the zone's own setback.
    public var zoneViolations: [Bool]
    public var lotAreaM2: Double?
    public var coveragePct: Double?
    public var coverageViolation: Bool

    public var hasViolation: Bool {
        lotSetbackViolation || structureSetbackViolation || coverageViolation
            || (poolCenterInsideLot == false)
            || equipment.contains { $0.poolViolation || $0.lotViolation }
            || zoneViolations.contains(true)
    }
}

public enum ComplianceEngine {
    public static func evaluate(site: SiteGeometry, rules: RuleProfile) -> ComplianceReport {
        let ref = site.poolCenter
        let pool = site.poolRing.map { Geo.llToXY($0, ref: ref) }

        // --- lot edges: for each edge, the shortest connector from any pool vertex ---
        var lotEdgeGaps: [EdgeGap] = []
        var insideLot: Bool?
        var lotXY: [XY]?
        if let lot = site.lot, lot.count >= 3 {
            let xy = lot.map { Geo.llToXY($0, ref: ref) }
            lotXY = xy
            for i in 0..<xy.count {
                let a = xy[i], b = xy[(i + 1) % xy.count]
                var best: Connector?
                for p in pool {
                    let r = Geo.closestPtSeg(p, a, b)
                    if best == nil || r.d < best!.d {
                        best = Connector(d: r.d, from: p, to: r.c)
                    }
                }
                if let best { lotEdgeGaps.append(EdgeGap(edgeIndex: i, connector: best)) }
            }
            lotEdgeGaps.sort { $0.connector.d < $1.connector.d }
            insideLot = Geo.pointInPoly(XY(x: 0, y: 0), xy)
        }
        let lotMin = lotEdgeGaps.first?.connector.d
        let lotViolation: Bool = {
            guard site.lot != nil else { return false }
            if insideLot == false { return true }
            if let setback = rules.propertyLineSetbackM, let lotMin { return lotMin < setback }
            return false
        }()

        // --- structures: shortest pool-vertex-to-edge connector per structure ---
        var structureGaps: [Connector?] = []
        for s in site.structures {
            guard s.count >= 3 else { structureGaps.append(nil); continue }
            let poly = s.map { Geo.llToXY($0, ref: ref) }
            var best: Connector?
            for p in pool {
                for i in 0..<poly.count {
                    let r = Geo.closestPtSeg(p, poly[i], poly[(i + 1) % poly.count])
                    if best == nil || r.d < best!.d {
                        best = Connector(d: r.d, from: p, to: r.c)
                    }
                }
            }
            structureGaps.append(best)
        }
        let structViolation: Bool = {
            guard let setback = rules.structureSetbackM else { return false }
            return structureGaps.contains { ($0?.d ?? .infinity) < setback }
        }()

        // --- equipment: nearest pool wall + nearest lot line ---
        var equipment: [EquipmentCheck] = []
        for (i, pinLL) in site.equipment.enumerated() {
            let p = Geo.llToXY(pinLL, ref: ref)
            let toPool = Geo.nearestOnPoly(p, pool)?.d
            let poolViol: Bool = {
                guard let clearance = rules.equipmentPoolClearanceM, let toPool else { return false }
                return toPool < clearance
            }()
            var toLot: Double?
            var lotViol = false
            if let lotXY {
                toLot = Geo.nearestOnPoly(p, lotXY)?.d
                // Web behavior: equipment is checked against the property-line
                // setback; a dedicated equipment-to-lot rule overrides it.
                if let limit = rules.equipmentLotSetbackM ?? rules.propertyLineSetbackM,
                   let toLot {
                    lotViol = toLot < limit
                }
            }
            equipment.append(EquipmentCheck(
                index: i, toPoolM: toPool, poolViolation: poolViol,
                toLotM: toLot, lotViolation: lotViol
            ))
        }

        // --- boundary zones (easements etc.) ---
        var zoneGaps: [Connector?] = []
        var zoneViolations: [Bool] = []
        for zone in site.zones {
            guard zone.points.count >= 3 else {
                zoneGaps.append(nil)
                zoneViolations.append(false)
                continue
            }
            let poly = zone.points.map { Geo.llToXY($0, ref: ref) }
            var best: Connector?
            for p in pool {
                for i in 0..<poly.count {
                    let r = Geo.closestPtSeg(p, poly[i], poly[(i + 1) % poly.count])
                    if best == nil || r.d < best!.d {
                        best = Connector(d: r.d, from: p, to: r.c)
                    }
                }
            }
            zoneGaps.append(best)
            let centerInside = Geo.pointInPoly(XY(x: 0, y: 0), poly)
            let underSetback = zone.setbackM.map { (best?.d ?? .infinity) < $0 } ?? false
            zoneViolations.append(centerInside || underSetback)
        }

        // --- lot coverage ---
        var lotArea: Double?
        var coveragePct: Double?
        var coverageViolation = false
        if let lot = site.lot, lot.count >= 3 {
            let area = Geo.polygonAreaM2(lot)
            lotArea = area
            if area > 0 {
                let pct = site.poolFootprintM2 / area * 100
                coveragePct = pct
                if let maxPct = rules.maxLotCoveragePct { coverageViolation = pct > maxPct }
            }
        }

        return ComplianceReport(
            ref: ref,
            lotEdgeGaps: lotEdgeGaps,
            poolCenterInsideLot: insideLot,
            lotSetbackViolation: lotViolation,
            structureGaps: structureGaps,
            structureSetbackViolation: structViolation,
            equipment: equipment,
            zoneGaps: zoneGaps,
            zoneViolations: zoneViolations,
            lotAreaM2: lotArea,
            coveragePct: coveragePct,
            coverageViolation: coverageViolation
        )
    }
}
