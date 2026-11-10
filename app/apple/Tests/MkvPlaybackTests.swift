#if os(macOS)
import AVFoundation
import XCTest
@testable import AIVision

/// MKV through the VLC backend (ADR-0008) against golden fixtures.
@MainActor
final class MkvPlaybackTests: XCTestCase {
    private func url(_ id: String) throws -> URL {
        let b = Bundle(for: Self.self)
        return try XCTUnwrap(b.url(forResource: id, withExtension: "mkv", subdirectory: "media")
            ?? b.url(forResource: id, withExtension: "mkv"))
    }

    func testMkvOpensWithVlcAndSeeks() async throws {
        let m = PlayerModel()
        await m.open(url: try url("synth_en_1080p60_001"))
        XCTAssertEqual(m.state, .ready, "\(m.state)")
        XCTAssertEqual(m.backendName, "VLC")
        XCTAssertEqual(m.duration, 12, accuracy: 0.2)
        XCTAssertEqual(m.videoSize, CGSize(width: 1920, height: 1080))
        let e0 = m.epoch
        for target in [7.8, 1.2, 10.0] {
            let ok = await m.seek(to: target)
            XCTAssertTrue(ok, "seek \(target)")
            XCTAssertEqual(m.currentTime, target, accuracy: 0.1, "seek \(target)")
        }
        XCTAssertEqual(m.epoch, e0 + 3)
        m.close()
    }

    /// Frames from VLC reach OCR and read the same subtitle as the MP4 (E2E for MKV).
    func testVlcFramesAreReadableByOcr() async throws {
        for (id, subs, hint) in [("synth_en_1080p60_001", Golden.en, LanguageHint.en),
                                 ("synth_ja_1080p60_001", Golden.ja, LanguageHint.ja)] {
            let e = VLCPlaybackEngine()
            _ = try await e.open(url: try url(id))
            let (start, end, ref) = subs[1]
            _ = await e.seek(to: (start + end) / 2)
            e.play(rate: 1); try await Task.sleep(nanoseconds: 300_000_000); e.pause()
            var frame: CVPixelBuffer?
            for _ in 0..<50 where frame == nil { frame = e.frames.nextFrame(); try await Task.sleep(nanoseconds: 20_000_000) }
            let pb = try XCTUnwrap(frame, "no frame from VLC")
            XCTAssertEqual(CVPixelBufferGetWidth(pb), 1920)
            var ocr = SubtitleOCR(); ocr.hint = hint
            let r = try XCTUnwrap(try ocr.recognize(pb), "\(id): no text")
            let cer = characterErrorRate(reference: ref, hypothesis: r.text)
            print("VLC OCR \(id): CER=\(cer) '\(r.text)'")
            XCTAssertLessThanOrEqual(cer, 0.05)
            e.close()
        }
    }

    /// OCR keeps reading VLC frames while playing (not only when paused), and no text in gaps.
    func testOcrDuringVlcPlayback() async throws {
        let e = VLCPlaybackEngine()
        _ = try await e.open(url: try url("synth_ja_1080p60_001"))
        e.play(rate: 1)
        var ocr = SubtitleOCR(); ocr.hint = .ja
        var seen = Set<String>(), wrong: [String] = []
        for _ in 0..<44 {
            try await Task.sleep(nanoseconds: 250_000_000)
            guard let pb = e.frames.nextFrame(), let r = try ocr.recognize(pb) else { continue }
            if Golden.ja.contains(where: { $0.2 == r.text }) { seen.insert(r.text) } else { wrong.append(r.text) }
        }
        e.close()
        XCTAssertEqual(seen.count, 3, "seen \(seen)")
        XCTAssertTrue(wrong.isEmpty, "unexpected OCR: \(wrong)")
    }

    func testMp4StillUsesAVFoundation() async throws {
        let m = PlayerModel()
        await m.open(url: try Golden.url("synth_en_1080p60_001"))
        XCTAssertEqual(m.backendName, "AVFoundation")
        m.close()
    }
}
#endif
