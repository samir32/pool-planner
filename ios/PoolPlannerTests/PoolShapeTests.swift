import XCTest
@testable import PoolPlanner

/// Sanity for the shape library. The ellipse/rect paths are pinned separately
/// by the web-app parity fixtures; these cover the added inground shapes.
final class PoolShapeTests: XCTestCase {
    private let center = LatLng(lat: 45.5, lng: -73.5)

    func testEveryShapeProducesAClosedRingInsideItsEnvelope() {
        for shape in PoolShapeKind.allCases {
            let aM = 5.0, bM = 2.5
            let ring = PoolShape.points(center: center, aM: aM, bM: bM, rotDeg: 0, shape: shape)
            XCTAssertGreaterThanOrEqual(ring.count, 4, "\(shape) ring too small")

            // every vertex must sit inside the requested envelope (+1 mm slack)
            for p in ring {
                let xy = Geo.llToXY(p, ref: center)
                XCTAssertLessThanOrEqual(abs(xy.x), aM + 1e-3, "\(shape) exceeds length")
                XCTAssertLessThanOrEqual(abs(xy.y), bM + 1e-3, "\(shape) exceeds width")
            }
            // and the envelope must actually be reached on both axes
            let xs = ring.map { abs(Geo.llToXY($0, ref: center).x) }.max() ?? 0
            let ys = ring.map { abs(Geo.llToXY($0, ref: center).y) }.max() ?? 0
            XCTAssertEqual(xs, aM, accuracy: 0.05, "\(shape) does not fill its length")
            XCTAssertEqual(ys, bM, accuracy: 0.05, "\(shape) does not fill its width")
        }
    }

    func testFootprintIsPositiveAndBoundedByTheRectangle() {
        let aM = 5.0, bM = 2.5
        let boundingArea = (2 * aM) * (2 * bM)
        for shape in PoolShapeKind.allCases {
            let area = PoolShape.footprintM2(aM: aM, bM: bM, shape: shape)
            XCTAssertGreaterThan(area, 0, "\(shape) has no area")
            XCTAssertLessThanOrEqual(area, boundingArea + 1e-9, "\(shape) exceeds its bounding box")
        }
        // the rectangle is the bound; everything rounded is strictly smaller
        XCTAssertEqual(PoolShape.footprintM2(aM: aM, bM: bM, shape: .rect), boundingArea, accuracy: 1e-9)
        for shape in [PoolShapeKind.oval, .kidney, .figure8, .roman, .grecian] {
            XCTAssertLessThan(PoolShape.footprintM2(aM: aM, bM: bM, shape: shape), boundingArea)
        }
    }

    /// A kidney is pinched on one side only; a figure 8 on both.
    func testWaistedShapesArePinchedWhereExpected() {
        func widthNearMiddle(_ shape: PoolShapeKind) -> (top: Double, bottom: Double) {
            let pts = PoolShape.normalizedOutline(shape).filter { abs($0.x) < 0.08 }
            return (pts.map(\.y).max() ?? 0, pts.map(\.y).min() ?? 0)
        }
        let kidney = widthNearMiddle(.kidney)
        XCTAssertLessThan(kidney.top, 0.85, "kidney should be indented on the +y side")
        XCTAssertLessThan(kidney.bottom, -0.85, "kidney should stay full on the -y side")

        let eight = widthNearMiddle(.figure8)
        XCTAssertLessThan(eight.top, 0.85, "figure 8 should pinch on +y")
        XCTAssertGreaterThan(eight.bottom, -0.85, "figure 8 should pinch on -y too")
    }

    /// The L shapes carve a notch out of one corner, so their area lands well
    /// under the rectangle but well over half of it.
    func testLShapesRemoveACorner() {
        let aM = 5.0, bM = 2.5
        let rect = PoolShape.footprintM2(aM: aM, bM: bM, shape: .rect)
        for shape in [PoolShapeKind.lazyL, .trueL] {
            let area = PoolShape.footprintM2(aM: aM, bM: bM, shape: shape)
            XCTAssertLessThan(area, rect * 0.95, "\(shape) should be smaller than the rectangle")
            XCTAssertGreaterThan(area, rect * 0.55, "\(shape) removed too much")
        }
    }
}
