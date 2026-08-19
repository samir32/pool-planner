import XCTest
@testable import PoolPlanner

final class ProjectStateTests: XCTestCase {
    private func makeState() -> ProjectState {
        var state = ProjectState()
        state.poolCenter = LatLng(lat: 45.5018, lng: -73.567)
        state.shape = .rect
        state.widthFt = 16
        state.lengthFt = 32
        state.rotationDeg = 45
        state.units = .imperial
        state.lot = [
            LatLng(lat: 45.5017, lng: -73.5673),
            LatLng(lat: 45.502, lng: -73.5676),
            LatLng(lat: 45.5021, lng: -73.5669),
        ]
        state.structures = [state.lot]
        state.pins = [PlacedPin(kind: .heatPump, position: LatLng(lat: 45.5019, lng: -73.5671))]
        state.rules = RuleProfile(name: "My town", propertyLineSetbackM: 2.0, maxLotCoveragePct: 10)
        state.scenarios = [Scenario(
            name: "Big pool", shape: .oval, widthFt: 18, lengthFt: 33,
            rotationDeg: 90, center: state.poolCenter, rules: state.rules
        )]
        return state
    }

    func testCodableRoundTrip() throws {
        let state = makeState()
        let data = try JSONEncoder().encode(state)
        let back = try JSONDecoder().decode(ProjectState.self, from: data)
        XCTAssertEqual(back, state)
    }

    func testStoreSaveAndLoad() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ProjectStore(url: url)
        XCTAssertNil(store.load())
        let state = makeState()
        store.save(state)
        XCTAssertEqual(store.load(), state)
    }

    func testStoreLoadIgnoresCorruptFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)
        XCTAssertNil(ProjectStore(url: url).load())
    }
}
