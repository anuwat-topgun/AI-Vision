import CoreImage
import CoreVideo
import Vision

/// OCR adapter (E03, FR-004) on Apple Vision. Runs on the caller's background queue;
/// never on the render or main thread. Only text + bbox + confidence leave this file.
enum LanguageHint: String, CaseIterable, Identifiable {
    case auto, en, ja
    var id: String { rawValue }
    var label: String { switch self { case .auto: "Auto"; case .en: "English"; case .ja: "日本語" } }
}

struct OcrResult: Equatable {
    var text: String
    var confidence: Float
    /// [left, top, width, height] normalized to the full frame, top-left origin (schema bbox).
    var bbox: CGRect
    var language: String // "en" | "ja"
}

struct SubtitleOCR {
    /// Region of interest, normalized, top-left origin. Default = bottom band (BOTTOM_REGION, §6.2).
    var roi = CGRect(x: 0.05, y: 0.62, width: 0.90, height: 0.36)
    var hint: LanguageHint = .auto

    func recognize(_ pixelBuffer: CVPixelBuffer) throws -> OcrResult? {
        try recognize(handler: VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]))
    }

    func recognize(_ image: CGImage) throws -> OcrResult? {
        try recognize(handler: VNImageRequestHandler(cgImage: image, options: [:]))
    }

    private func recognize(handler: VNImageRequestHandler) throws -> OcrResult? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = switch hint {
        case .en: ["en-US"]
        case .ja: ["ja-JP", "en-US"]
        case .auto: ["ja-JP", "en-US"] // ja model also reads Latin text
        }
        // Vision ROI uses bottom-left origin.
        request.regionOfInterest = CGRect(x: roi.minX, y: 1 - roi.maxY, width: roi.width, height: roi.height)
        try handler.perform([request])
        let obs = (request.results ?? [])
            .compactMap { o -> (String, Float, CGRect)? in
                guard let c = o.topCandidates(1).first, c.confidence > 0.2 else { return nil }
                // boundingBox is relative to the ROI; convert to full frame, top-left origin.
                let b = o.boundingBox
                let full = CGRect(x: roi.minX + b.minX * roi.width,
                                  y: roi.maxY - (b.minY + b.height) * roi.height,
                                  width: b.width * roi.width, height: b.height * roi.height)
                return (c.string, c.confidence, full)
            }
            .filter { $0.2.height > 0.015 } // ignore tiny UI text
            .sorted { $0.2.minY < $1.2.minY }
        guard !obs.isEmpty else { return nil }
        let text = Self.joinLines(obs.map(\.0))
        let conf = obs.map(\.1).reduce(0, +) / Float(obs.count)
        let box = obs.dropFirst().reduce(obs[0].2) { $0.union($1.2) }
        return OcrResult(text: text, confidence: conf, bbox: box, language: Self.detectLanguage(text))
    }

    /// Japanese lines join without spaces; Latin lines with one space (§6.1 step 6).
    static func joinLines(_ lines: [String]) -> String {
        lines.map { $0.trimmingCharacters(in: .whitespaces) }.reduce("") { acc, line in
            guard let last = acc.last, let first = line.first else { return acc + line }
            return acc + (isCJK(last) || isCJK(first) ? "" : " ") + line
        }
    }

    static func isCJK(_ c: Character) -> Bool {
        c.unicodeScalars.contains { (0x3000...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) || (0xFF00...0xFFEF).contains($0.value) }
    }

    /// Any kana/kanji → ja; never silently treat Japanese as English (§6.5).
    static func detectLanguage(_ text: String) -> String {
        text.contains(where: isCJK) ? "ja" : "en"
    }
}
