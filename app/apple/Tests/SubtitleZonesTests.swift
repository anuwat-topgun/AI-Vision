import AVFoundation
import CoreImage
import XCTest
@testable import AIVision

final class SubtitleZonesTests: XCTestCase {
    func testZoneStoreRoundTrip() {
        let key = "test.zones.\(UUID())"
        let z = [CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.1), CGRect(x: 0.2, y: 0.1, width: 0.3, height: 0.05)]
        SubtitleZoneStore.save(z, key)
        XCTAssertEqual(SubtitleZoneStore.load(key), z)
        UserDefaults.standard.removeObject(forKey: key)
    }

    func testEachZoneTapSeesEveryNewFrame() throws {
        let sink = CaptureFrameSink()
        let a = sink.tap(), b = sink.tap()
        XCTAssertNil(a.nextFrame())
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 4, 4, kCVPixelFormatType_32BGRA, nil, &pb)
        var sb: CMSampleBuffer?
        var fmt: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pb!, formatDescriptionOut: &fmt)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pb!, formatDescription: fmt!,
                                                 sampleTiming: &timing, sampleBufferOut: &sb)
        let conn = AVCaptureConnection(inputPorts: [], output: AVCaptureVideoDataOutput())
        sink.captureOutput(AVCaptureVideoDataOutput(), didOutput: sb!, from: conn)
        XCTAssertNotNil(a.nextFrame(), "zone A gets the frame")
        XCTAssertNotNil(b.nextFrame(), "zone B gets the same frame too")
        XCTAssertNil(a.nextFrame(), "no repeat until a newer frame")
    }

    func testBackgroundColourSampledAroundTextBox() {
        // Blue panel with a white text bar in the middle.
        let panel = CIImage(color: CIColor(red: 0, green: 0.2, blue: 0.8)).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 100))
        let text = CIImage(color: .white).cropped(to: CGRect(x: 50, y: 45, width: 100, height: 10))
        let img = text.composited(over: panel)
        let box = CGRect(x: 0.25, y: 0.45, width: 0.5, height: 0.1) // top-left normalized
        let c = SubtitleOCR.backgroundColor(around: box, in: img)!
        XCTAssertEqual(c.z, 0.8, accuracy: 0.05)
        XCTAssertLessThan(c.x, 0.1, "white text must not bleed into the sampled panel colour")
    }
}
