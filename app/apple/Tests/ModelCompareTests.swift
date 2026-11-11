import XCTest
@testable import AIVision

/// Local-only model comparison (KI-031, ADR-0010 follow-up). Run with
/// `TEST_RUNNER_AIVISION_COMPARE=1 xcodebuild test -only-testing:AIVisionTests/ModelCompareTests`.
final class ModelCompareTests: XCTestCase {
    static let models = ["Qwen3-4B-Instruct-2507-Q4_K_M", "typhoon2.5-qwen3-4b-q4_k_m", "typhoon-translate1.5-4b-q4_k_m"]

    func testCompareModelsOnGameLines() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["AIVISION_COMPARE"] == "1", "set AIVISION_COMPARE=1")
        let dir = try XCTUnwrap(Bundle.main.url(forResource: "profiles", withExtension: nil))
        func profile(_ id: String) throws -> GameProfile {
            try GameProfile.fromJson(json: String(contentsOf: dir.appendingPathComponent("\(id).json"), encoding: .utf8))
        }
        let ff = try profile("final_fantasy_vii_remake"), gb = try profile("granblue_fantasy_relink")
        let cases: [(GameProfile?, String?, String, FfiSourceLanguage)] = [
            (ff, "Barret", "Shinra's sucking the Mako right outta the planet!", .english),
            (ff, "Cloud", "Not interested.", .english),
            (ff, "Aerith", "You're a funny one, you know that?", .english),
            (ff, "Tifa", "Thank you, Cloud. Really.", .english),
            (ff, "Cloud", "I'm SOLDIER. First Class.", .english),
            (ff, "Barret", "Don't you dare walk away from me, Spiky!", .english),
            (gb, "Vyrn", "Come on, let's get back to the Grandcypher!", .english),
            (gb, "Lyria", "Thank you so much, everyone.", .english),
            (gb, "Rolan", "That being said, I can't just leave these people here unprotected.", .english),
            (gb, "Katalina", "Stay behind me, Lyria!", .english),
            (gb, "Io", "Hmph! I could've handled that myself, you know.", .english),
            (nil, nil, "Leave it to me!", .english),
            (nil, nil, "What the hell are you doing?!", .english),
            (nil, nil, "夜明けまでに門へ行こう。", .japanese),
            (nil, nil, "ありがとうございます。", .japanese),
        ]
        var columns: [[String]] = []
        var timing: [String] = []
        for name in Self.models {
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Models/\(name).gguf")
            guard FileManager.default.fileExists(atPath: url.path) else { columns.append(cases.map { _ in "(missing)" }); continue }
            let m = try await LlamaTranslator.load(url: url)
            var col: [String] = [], ms: [Int] = []
            for (p, sp, src, lang) in cases {
                var r = TranslationRequest(sourceText: src, language: lang, history: [])
                r.profile = p; r.speaker = p.map { $0.speakerHint(speaker: sp) } ?? sp
                let t0 = Date()
                let o = try await m.translate(r)
                ms.append(Int(Date().timeIntervalSince(t0) * 1000))
                let out: String = if case .translated(let t) = o { t } else { "⟨\(o)⟩" }
                col.append(out)
            }
            m.shutdown()
            let sorted = ms.sorted()
            timing.append("\(name): P50 \(sorted[sorted.count / 2]) ms, max \(sorted.last!) ms (prompt \(m.promptVersion))")
            columns.append(col)
        }
        var md = "| Speaker | Source | " + Self.models.joined(separator: " | ") + " |\n|" + String(repeating: "---|", count: 2 + Self.models.count) + "\n"
        for (i, c) in cases.enumerated() {
            md += "| \(c.1 ?? "–") | \(c.2) | " + columns.map { $0[i].replacingOccurrences(of: "|", with: "/") }.joined(separator: " | ") + " |\n"
        }
        md += "\n" + timing.map { "- \($0)" }.joined(separator: "\n")
        print("MODEL_COMPARE_BEGIN\n\(md)\nMODEL_COMPARE_END")
    }
}
