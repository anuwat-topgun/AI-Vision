import XCTest
@testable import AIVision

final class CoreBridgeTests: XCTestCase {
    func testApiVersion() { XCTAssertEqual(coreApiVersion(), 1) }

    /// AC-010 via FFI: a result from before a seek is stale.
    func testSeekMakesOldEpochStale() {
        let s = CoreSession(sourceId: "file:a")
        let old = s.epoch()
        _ = s.bump(reason: .seek)
        XCTAssertFalse(s.isCurrent(sourceId: "file:a", epoch: old))
        XCTAssertTrue(s.isCurrent(sourceId: "file:a", epoch: old + 1))
    }
}
