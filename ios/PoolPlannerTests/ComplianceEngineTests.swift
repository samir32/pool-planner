import XCTest
@testable import PoolPlanner

/// Behavior tests for rule toggling — the engine measures everything but only
/// flags violations for rules the profile enables.
final class ComplianceEngineTests: XCTestCase {
    /// 10×10 m square lot centered on the pool; 4×4 m square pool → 3 m gap on
    /// every side.
    private func makeSite() -> SiteGeometry {
        let center = LatLng(lat: 45.5, lng: -73.5)
        func corner(_ dx: Double, _ dy: Double) -> LatLng { Geo.offset(center, dx: dx, dy: dy) }
        let lot = [corner(-5, -5), corner(5, -5), corner(5, 5), corner(-5, 5)]
        let ring = PoolShape.points(center: center, aM: 2, bM: 2, rotDeg: 0, shape: .rect)
        return SiteGeometry(
            poolCenter: center,
            poolRing: ring,
            poolFootprintM2: PoolShape.footprintM2(aM: 2, bM: 2, shape: .rect),
            lot: lot,
            structures: [],
            equipment: [Geo.offset(center, dx: 2.5, dy: 0)] // 0.5 m from pool wall
        )
    }

    func testViolationsFollowEnabledRules() {
        let site = makeSite()

        // 3 m gap vs 1.5 m setback → OK; 0.5 m equipment clearance vs 1 m → violation
        var rules = RuleProfile(name: "t")
        var report = ComplianceEngine.evaluate(site: site, rules: rules)
        XCTAssertEqual(report.lotEdgeGaps.first!.connector.d, 3.0, accuracy: 1e-9)
        XCTAssertFalse(report.lotSetbackViolation)
        XCTAssertTrue(report.equipment[0].poolViolation)
        XCTAssertEqual(report.equipment[0].toPoolM!, 0.5, accuracy: 1e-9)
        XCTAssertTrue(report.hasViolation)

        // tighten the lot setback beyond the gap → violation appears
        rules.propertyLineSetbackM = 3.5
        report = ComplianceEngine.evaluate(site: site, rules: rules)
        XCTAssertTrue(report.lotSetbackViolation)

        // turn rules off → measured values remain, violations disappear
        rules = RuleProfile(
            name: "off", propertyLineSetbackM: nil, structureSetbackM: nil,
            equipmentPoolClearanceM: nil
        )
        report = ComplianceEngine.evaluate(site: site, rules: rules)
        XCTAssertFalse(report.lotSetbackViolation)
        XCTAssertFalse(report.equipment[0].poolViolation)
        XCTAssertFalse(report.equipment[0].lotViolation)
        XCTAssertNotNil(report.equipment[0].toPoolM)
        XCTAssertFalse(report.hasViolation)
    }

    func testCoverageRule() {
        let site = makeSite() // 16 m² pool on a 100 m² lot = 16%
        var rules = RuleProfile(name: "t", maxLotCoveragePct: 15)
        var report = ComplianceEngine.evaluate(site: site, rules: rules)
        XCTAssertEqual(report.coveragePct!, 16.0, accuracy: 1e-3)
        XCTAssertTrue(report.coverageViolation)

        rules.maxLotCoveragePct = nil
        report = ComplianceEngine.evaluate(site: site, rules: rules)
        XCTAssertEqual(report.coveragePct!, 16.0, accuracy: 1e-3)
        XCTAssertFalse(report.coverageViolation)
    }

    func testPoolCenterOutsideLotIsViolation() {
        var site = makeSite()
        let far = Geo.offset(site.poolCenter, dx: 50, dy: 0)
        site.poolRing = PoolShape.points(center: far, aM: 2, bM: 2, rotDeg: 0, shape: .rect)
        site.poolCenter = far
        // lot stays where it was; pool center is now outside it
        let report = ComplianceEngine.evaluate(site: site, rules: RuleProfile(name: "t"))
        XCTAssertEqual(report.poolCenterInsideLot, false)
        XCTAssertTrue(report.lotSetbackViolation)
    }

    func testEquipmentLotRuleOverridesPropertySetback() {
        let site = makeSite() // equipment sits 2.5 m from lot edge
        // property setback 3 m would flag it…
        var rules = RuleProfile(name: "t", propertyLineSetbackM: 3.0)
        var report = ComplianceEngine.evaluate(site: site, rules: rules)
        XCTAssertTrue(report.equipment[0].lotViolation)
        // …but a dedicated 1 m equipment-to-lot rule takes precedence
        rules.equipmentLotSetbackM = 1.0
        report = ComplianceEngine.evaluate(site: site, rules: rules)
        XCTAssertFalse(report.equipment[0].lotViolation)
    }
}
