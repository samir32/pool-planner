import XCTest
@testable import PoolPlanner

final class UnitFormatterTests: XCTestCase {
    func testMetricMatchesWebFmtM() {
        let f = UnitFormatter(system: .metric)
        XCTAssertEqual(f.distance(1.47), "1.45 m") // nearest 5 cm
        XCTAssertEqual(f.distance(1.499), "1.50 m")
        XCTAssertEqual(f.distance(0), "0.00 m")
        XCTAssertEqual(f.distance(12.301), "12.30 m")
    }

    func testImperialRoundsToNearestInch() {
        let f = UnitFormatter(system: .imperial)
        XCTAssertEqual(f.distance(1.5), "4 ft 11 in") // 59.06 in
        XCTAssertEqual(f.distance(Geo.metersPerFoot * 10), "10 ft")
        XCTAssertEqual(f.distance(0.0254 * 7), "7 in")
    }

    func testMixedModeSplitsDimsAndSetbacks() {
        let f = UnitFormatter(system: .mixed)
        // setbacks in meters, pool dims in feet — the web app's convention
        XCTAssertEqual(f.distance(1.5), "1.50 m")
        XCTAssertEqual(f.poolDimension(Geo.metersPerFoot * 21), "21 ft")
    }

    func testAreas() {
        XCTAssertEqual(UnitFormatter(system: .metric).area(41.81), "41.8 m²")
        XCTAssertEqual(UnitFormatter(system: .imperial).area(Geo.metersPerFoot * Geo.metersPerFoot * 450), "450 ft²")
    }
}
