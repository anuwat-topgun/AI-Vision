import AVFoundation
import XCTest
@testable import AIVision

final class CaptureFormatTests: XCTestCase {
    private func f(_ w: Int, _ h: Int, _ fps: Double, _ pf: String = "420v", _ i: Int = 0) -> CaptureFormatOption {
        CaptureFormatOption(width: w, height: h, maxFps: fps, pixelFormat: pf, index: i)
    }

    func testPrefers1080p60UncompressedThenFallsBack() { // README §5.2 ladder
        XCTAssertEqual(CaptureFormatOption.preferred([f(1280, 720, 60), f(1920, 1080, 60, "dmb1", 1), f(1920, 1080, 60, "yuvs", 2)])?.index, 2)
        XCTAssertEqual(CaptureFormatOption.preferred([f(1920, 1080, 30, "420v", 3), f(1280, 720, 60, "420v", 4)])?.index, 3)
        XCTAssertEqual(CaptureFormatOption.preferred([f(1280, 720, 60, "420v", 5), f(640, 480, 30, "420v", 6)])?.index, 5)
        XCTAssertEqual(CaptureFormatOption.preferred([f(3840, 2160, 30, "420v", 7), f(1600, 900, 30, "420v", 8)])?.index, 8,
                       "no 4K by default (§5.2 does not assume 4K)")
        XCTAssertNil(CaptureFormatOption.preferred([]))
    }

    func testFourCC() { XCTAssertEqual(LiveCaptureEngine.fourcc(0x34323076), "420v") }
}

/// Lists real UVC devices + formats (no camera permission needed). Skips when none (CI).
@MainActor
final class CaptureDiscoveryTests: XCTestCase {
    func testDiscoverDevicesAndFormats() throws {
        let e = LiveCaptureEngine()
        try XCTSkipIf(e.devices.isEmpty, "no UVC device connected")
        for d in e.devices {
            e.select(deviceId: d.id)
            XCTAssertFalse(e.formats.isEmpty, "\(d.name) has no formats")
            let pick = CaptureFormatOption.preferred(e.formats)
            print("UVC_DEVICE \(d.name) [\(d.model)] formats=\(e.formats.count) auto=\(pick?.label ?? "-")")
            for fm in e.formats.prefix(8) { print("   \(fm.label)") }
        }
    }
}
