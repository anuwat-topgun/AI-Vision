import AVFoundation
import XCTest
@testable import AIVision

/// Fixture subtitles (mirror fixtures/manifest.yaml).
enum Golden {
    static let en: [(Double, Double, String)] = [
        (1.2, 3.9, "We should reach the gate before dawn."),
        (4.5, 7.2, "Keep your lantern low. The guards are near."),
        (7.8, 10.8, "If we split up, meet me at the old well."),
    ]
    static let ja: [(Double, Double, String)] = [
        (1.6, 4.2, "夜明けまでに門へ行こう。"),
        (4.8, 7.5, "灯りを低くして。見張りが近い。"),
        (8.1, 11.0, "はぐれたら、古い井戸で会おう。"),
    ]
    static func url(_ id: String) throws -> URL {
        let b = Bundle(for: SubtitlePipelineTests.self)
        return try XCTUnwrap(b.url(forResource: id, withExtension: "mp4", subdirectory: "media")
            ?? b.url(forResource: id, withExtension: "mp4"))
    }
    static func frame(_ id: String, at t: Double) async throws -> CGImage {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: try url(id)))
        gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
        return try await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
    }
}

final class NoFrames: FrameSource { func nextFrame() -> CVPixelBuffer? { nil } }

final class FakeTranslator: SubtitleTranslator, @unchecked Sendable {
    let modelId = "fake", modelRevision = "1", quantizationId = "none"
    var promptVersion = "p2"
    var delayNs: UInt64 = 0
    var calls = 0
    var outcome: ((String) -> TranslationOutcome)?
    var lastRequest: TranslationRequest?
    func translate(_ request: TranslationRequest) async throws -> TranslationOutcome {
        calls += 1; lastRequest = request
        try await Task.sleep(nanoseconds: delayNs)
        return outcome?(request.sourceText) ?? .translated("TH(\(request.sourceText))")
    }
}

@MainActor
final class SubtitlePipelineTests: XCTestCase {
    /// AC-005 / AC-006 software gate on golden fixtures. Threshold is a placeholder until D-008.
    func testOcrCharacterErrorRateOnFixtures() async throws {
        var report: [String] = []
        for (id, subs, hint) in [("synth_en_1080p60_001", Golden.en, LanguageHint.en),
                                 ("synth_ja_1080p60_001", Golden.ja, LanguageHint.ja)] {
            var ocr = SubtitleOCR(); ocr.hint = hint
            for (start, end, ref) in subs {
                let img = try await Golden.frame(id, at: (start + end) / 2)
                let r = try XCTUnwrap(try ocr.recognize(img), "\(id) no text at \(start)")
                let cer = characterErrorRate(reference: ref, hypothesis: r.text)
                report.append(String(format: "%@ %.1fs CER=%.3f lang=%@ '%@'", id, start, cer, r.language, r.text))
                XCTAssertLessThanOrEqual(cer, 0.05, "\(id): '\(r.text)' vs '\(ref)'")
                XCTAssertEqual(r.language, id.contains("_ja_") ? "ja" : "en")
                XCTAssertGreaterThan(r.bbox.minY, 0.75, "bbox should be in the bottom band")
            }
            // Between subtitles there must be no text (detection false positive check).
            let empty = try await Golden.frame(id, at: 0.5)
            XCTAssertNil(try ocr.recognize(empty), "\(id) false positive")
        }
        print("OCR report:\n" + report.joined(separator: "\n"))
    }

    /// AC-010 / E2E-03: a translation finishing after a seek must be dropped.
    func testStaleTranslationDroppedAfterSeek() async throws {
        let p = SubtitlePipeline()
        let fake = FakeTranslator(); fake.delayNs = 200_000_000
        p.translator = fake
        let s = CoreSession(sourceId: "file:test")
        p.attach(frames: NoFrames(), session: s)
        let tag = (s.sourceId(), s.epoch())
        let r = OcrResult(text: "Hello", confidence: 0.9, bbox: CGRect(x: 0.2, y: 0.8, width: 0.6, height: 0.1), language: "en")
        p.handle(r, ocrMs: 1, tag: tag)
        p.handle(r, ocrMs: 1, tag: tag) // stable → translation starts
        XCTAssertEqual(p.overlay?.status, .translating)
        _ = s.bump(reason: .seek); p.invalidate()
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNil(p.overlay, "stale translation must not appear")
        p.detach()
    }

    func testGameUiLabelsAreDroppedFromSubtitleBlock() {
        // Big 2-line subtitle plus small "Auto Play" / "Story Logs" buttons below it.
        let lines: [(String, CGRect)] = [
            ("Line one", CGRect(x: 0.2, y: 0.78, width: 0.6, height: 0.05)),
            ("Line two", CGRect(x: 0.2, y: 0.84, width: 0.6, height: 0.05)),
            ("Auto Play", CGRect(x: 0.75, y: 0.95, width: 0.08, height: 0.025)),
            ("Story Logs", CGRect(x: 0.85, y: 0.95, width: 0.09, height: 0.025)),
        ]
        XCTAssertEqual(SubtitleOCR.subtitleBlock(lines), [lines[0].1, lines[1].1])
    }

    func testSameSizeCornerLabelsAndNameTagAreDropped() {
        // Captured game frame: name tag, corner buttons and dialogue all share one small font.
        let lines: [(String, CGRect)] = [
            ("Rolan", CGRect(x: 0.25, y: 0.765, width: 0.04, height: 0.022)),
            ("Autoplay", CGRect(x: 0.06, y: 0.79, width: 0.06, height: 0.022)),
            ("Story Log", CGRect(x: 0.86, y: 0.79, width: 0.07, height: 0.022)),
            ("That being said, I can't just leave these people here unprotected.",
             CGRect(x: 0.27, y: 0.82, width: 0.46, height: 0.022)),
        ]
        XCTAssertEqual(SubtitleOCR.subtitleBlock(lines), [lines[3].1])
    }

    func testShownThenClearedWhenTextVanishes() async throws { // AC-011
        let p = SubtitlePipeline()
        p.translator = FakeTranslator()
        let s = CoreSession(sourceId: "file:t2")
        p.attach(frames: NoFrames(), session: s)
        let tag = (s.sourceId(), s.epoch())
        let r = OcrResult(text: "Hi there", confidence: 0.9, bbox: .zero, language: "en")
        p.handle(r, ocrMs: 1, tag: tag); p.handle(r, ocrMs: 1, tag: tag)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(p.overlay?.thai, "TH(Hi there)")
        p.handle(nil, ocrMs: 1, tag: tag); p.handle(nil, ocrMs: 1, tag: tag); p.handle(nil, ocrMs: 1, tag: tag)
        XCTAssertNotNil(p.overlay, "Thai is held briefly after the source vanishes (no blink)")
        try await Task.sleep(nanoseconds: UInt64((SubtitlePipeline.holdAfterVanish + 0.2) * 1e9))
        XCTAssertNil(p.overlay)
        // Same text again: history now contains it, so the context differs and the cache key
        // differs too (§8 history fingerprint) — the spec prefers correctness over hit rate.
        p.handle(r, ocrMs: 1, tag: tag); p.handle(r, ocrMs: 1, tag: tag)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(p.overlay?.thai, "TH(Hi there)")
        p.detach()
    }
}

