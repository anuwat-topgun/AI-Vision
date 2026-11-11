import XCTest
@testable import AIVision

/// Prompt p3 (ADR-0010): game profile + speaker. Pipeline wiring uses a fake translator;
/// the A/B table needs the local model (skipped in CI).
@MainActor
final class TranslationP3PipelineTests: XCTestCase {
    static let profileJSON = """
    {"id":"t","title":"T","glossary":[{"source":"Mako","thai":"มาโค"}],
     "characters":[{"name":"Cloud","voice":"male, terse"}]}
    """

    func testProfileAndSpeakerReachTranslatorAndKey() async throws {
        let fake = FakeTranslator()
        let p = SubtitlePipeline(); p.translator = fake
        p.profile = try GameProfile.fromJson(json: Self.profileJSON)
        var speaker: String? = "CLOUD"
        p.speakerSource = { speaker }
        let s = CoreSession(sourceId: "file:p3")
        p.attach(frames: NoFrames(), session: s)
        let tag = (s.sourceId(), s.epoch())
        let r = OcrResult(text: "Let's go.", confidence: 0.9, bbox: .zero, language: "en")
        p.handle(r, ocrMs: 1, tag: tag); p.handle(r, ocrMs: 1, tag: tag)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(fake.lastRequest?.speaker, "Cloud (male, terse)")
        XCTAssertEqual(fake.lastRequest?.profile?.id(), "t")
        p.detach()
        speaker = nil
    }

    func testSpeakerZoneOnlyReadsName() {
        let p = SubtitlePipeline(); p.translates = false
        let s = CoreSession(sourceId: "file:sp")
        p.attach(frames: NoFrames(), session: s)
        let r = OcrResult(text: "Barret", confidence: 0.9, bbox: .zero, language: "en")
        p.handle(r, ocrMs: 1, tag: (s.sourceId(), s.epoch())); p.handle(r, ocrMs: 1, tag: (s.sourceId(), s.epoch()))
        XCTAssertEqual(p.speakerText, "Barret")
        XCTAssertNil(p.overlay, "speaker zones are never translated or drawn")
        p.detach()
    }

    func testBundledProfilesParse() throws {
        let dir = try XCTUnwrap(Bundle.main.url(forResource: "profiles", withExtension: nil))
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        XCTAssertGreaterThanOrEqual(files.count, 2)
        for f in files { XCTAssertNoThrow(try GameProfile.fromJson(json: String(contentsOf: f, encoding: .utf8)), f.lastPathComponent) }
    }
}

final class TranslationModelP3Tests: XCTestCase {
    func testP2VersusP3WithProfileAndSpeaker() async throws {
        let m = try await TranslationModelP2Tests().model()
        let dir = try XCTUnwrap(Bundle.main.url(forResource: "profiles", withExtension: nil))
        func profile(_ id: String) throws -> GameProfile {
            try GameProfile.fromJson(json: String(contentsOf: dir.appendingPathComponent("\(id).json"), encoding: .utf8))
        }
        let ff = try profile("final_fantasy_vii_remake"), gb = try profile("granblue_fantasy_relink")
        let cases: [(GameProfile, String?, String)] = [
            (ff, "Barret", "Shinra's sucking the Mako right outta the planet!"),
            (ff, "Cloud", "Not interested."),
            (ff, "Aerith", "You're a funny one, you know that?"),
            (ff, "Tifa", "Thank you, Cloud. Really."),
            (ff, "Cloud", "I'm SOLDIER. First Class."),
            (gb, "Vyrn", "Come on, let's get back to the Grandcypher!"),
            (gb, "Lyria", "Thank you so much, everyone."),
            (gb, "Rolan", "That being said, I can't just leave these people here unprotected."),
            (gb, "Katalina", "Stay behind me, Lyria!"),
        ]
        var rows: [String] = []
        var glossaryHits = 0
        for (p, sp, src) in cases {
            let base = TranslationRequest(sourceText: src, language: .english, history: [])
            let a = try await m.translate(base, promptVersion: "p2")
            var withP = base; withP.profile = p; withP.speaker = p.speakerHint(speaker: sp)
            let b = try await m.translate(withP, promptVersion: "p3")
            let tb: String = if case .translated(let t) = b { t } else { "\(b)" }
            let ta: String = if case .translated(let t) = a { t } else { "\(a)" }
            if src.contains("Mako") && tb.contains("มาโค") { glossaryHits += 1 }
            if let sp { XCTAssertFalse(tb.hasPrefix(sp + ":"), "speaker label leaked: \(tb)") }
            rows.append("[\(sp ?? "-")] \(src)\n   p2: \(ta)\n   p3: \(tb)")
        }
        print("P3_AB_TABLE\n" + rows.joined(separator: "\n"))
        XCTAssertEqual(glossaryHits, 1, "glossary term Mako → มาโค")
    }
}

final class LanguageRouterTests: XCTestCase {
    func testEnglishAndJapaneseGoToDifferentModels() async throws {
        let en = FakeTranslator(), ja = FakeTranslator()
        en.outcome = { _ in .translated("EN") }; ja.outcome = { _ in .translated("JA") }
        let r = LanguageRouter(english: en, other: ja)
        let a = try await r.translate(TranslationRequest(sourceText: "Hi", language: .english, history: []))
        let b = try await r.translate(TranslationRequest(sourceText: "やあ", language: .japanese, history: []))
        XCTAssertEqual(a, .translated("EN")); XCTAssertEqual(b, .translated("JA"))
        XCTAssertTrue(r.modelId.hasPrefix("en:fake+ja:fake"))
    }

    func testTyphoonTranslateFileDetection() {
        XCTAssertTrue(ModelStore.isTyphoonTranslate(URL(fileURLWithPath: "/m/typhoon-translate1.5-4b-q4_k_m.gguf")))
        XCTAssertFalse(ModelStore.isTyphoonTranslate(URL(fileURLWithPath: "/m/typhoon2.5-qwen3-4b-q4_k_m.gguf")))
    }
}
