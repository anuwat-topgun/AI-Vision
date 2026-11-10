import AVFoundation
import XCTest
@testable import AIVision

/// E02 against golden fixtures (fixtures/manifest.yaml). AC-001/AC-002 software part;
/// device evidence still required for QA-001/QA-002.
@MainActor
final class FilePlaybackTests: XCTestCase {
    private func fixture(_ id: String) throws -> URL {
        let bundle = Bundle(for: Self.self)
        return try XCTUnwrap(bundle.url(forResource: id, withExtension: "mp4", subdirectory: "media")
            ?? bundle.url(forResource: id, withExtension: "mp4"), "fixture \(id) not bundled")
    }

    func testFixturesDecodeAs1080p60() async throws {
        for id in ["synth_en_1080p60_001", "synth_ja_1080p60_001"] {
            let asset = AVURLAsset(url: try fixture(id))
            let (playable, duration) = try await asset.load(.isPlayable, .duration)
            XCTAssertTrue(playable, id)
            XCTAssertEqual(duration.seconds, 12, accuracy: 0.1, id)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            let track = try XCTUnwrap(videoTracks.first)
            let (size, fps) = try await track.load(.naturalSize, .nominalFrameRate)
            XCTAssertEqual(size, CGSize(width: 1920, height: 1080), id)
            XCTAssertEqual(fps, 60, accuracy: 0.5, id)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            XCTAssertFalse(audioTracks.isEmpty, "\(id) audio")
        }
    }

    func testOpenAndAccurateSeekBumpsEpoch() async throws { // AC-002 media time after seek, AC-010 epoch
        let m = PlayerModel()
        await m.open(url: try fixture("synth_en_1080p60_001"))
        XCTAssertEqual(m.state, .ready)
        XCTAssertEqual(m.duration, 12, accuracy: 0.1)
        let e0 = m.epoch
        for target in [7.8, 1.2, 10.0, 0.0] {
            let finished = await m.seek(to: target)
            XCTAssertTrue(finished, "seek \(target) completed")
            XCTAssertEqual(m.currentTime, target, accuracy: 1.0 / 60 + 0.001, "seek \(target)")
        }
        XCTAssertEqual(m.epoch, e0 + 4)
        await m.skip(-10) // clamps at 0
        XCTAssertEqual(m.currentTime, 0, accuracy: 0.02)
        await m.seek(to: 99) // clamps at duration
        XCTAssertEqual(m.currentTime, 12, accuracy: 0.1)
    }

    func testUnsupportedFileShowsError() async throws { // NFR-009, AC-033 (media part)
        let bad = FileManager.default.temporaryDirectory.appendingPathComponent("corrupt.mp4")
        try Data("not a video".utf8).write(to: bad)
        let m = PlayerModel()
        await m.open(url: bad)
        guard case .failed = m.state else { return XCTFail("expected failure, got \(m.state)") }
        XCTAssertNil(m.session)
    }
}
