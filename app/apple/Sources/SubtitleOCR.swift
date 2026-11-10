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
    /// Average colour of the box behind the text (RGB 0–1), when sampled from a pixel buffer.
    var background: SIMD3<Float>? = nil
    /// Height of one source text line (normalized), used to size Thai like the original.
    var lineHeight: CGFloat? = nil
}

struct SubtitleOCR {
    /// Region of interest, normalized, top-left origin. Default = bottom band (BOTTOM_REGION, §6.2).
    static let defaultRoi = CGRect(x: 0.05, y: 0.62, width: 0.90, height: 0.36)
    var roi = SubtitleOCR.defaultRoi
    var hint: LanguageHint = .auto

    func recognize(_ pixelBuffer: CVPixelBuffer) throws -> OcrResult? {
        guard var r = try recognize(handler: VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]))
        else { return nil }
        r.background = Self.backgroundColor(around: r.bbox, in: CIImage(cvPixelBuffer: pixelBuffer))
        return r
    }

    private static let ciContext = CIContext(options: [.workingColorSpace: NSNull()])

    /// Mean colour of thin strips just above and below the text box: the panel behind the subtitle.
    static func backgroundColor(around box: CGRect, in image: CIImage) -> SIMD3<Float>? {
        let e = image.extent
        guard e.width > 0, box.width > 0 else { return nil }
        let strip = max(2, box.height * e.height * 0.25)
        // CIImage origin is bottom-left; box is top-left normalized.
        let x = e.minX + box.minX * e.width, w = box.width * e.width
        let top = e.maxY - box.minY * e.height, bottom = e.maxY - box.maxY * e.height
        var sum = SIMD3<Float>(repeating: 0), n: Float = 0
        for r in [CGRect(x: x, y: top + 1, width: w, height: strip),
                  CGRect(x: x, y: bottom - 1 - strip, width: w, height: strip)] {
            let c = r.intersection(e)
            guard !c.isNull, c.width >= 1, c.height >= 1 else { continue }
            let avg = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: c)])
            var px = [UInt8](repeating: 0, count: 4)
            ciContext.render(avg, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                             format: .RGBA8, colorSpace: nil)
            sum += SIMD3(Float(px[0]), Float(px[1]), Float(px[2])) / 255; n += 1
        }
        return n > 0 ? sum / n : nil
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
        let lines = Self.subtitleBlock(obs.map { ($0.0, $0.2) }, centerX: roi.midX, zoneWidth: roi.width)
        let kept = obs.filter { o in lines.contains { $0 == o.2 } }
        guard !kept.isEmpty else { return nil }
        return Self.result(kept)
    }

    /// Game screens put UI labels ("Auto Play", "Story Logs"…) near the subtitle. Keep only the
    /// subtitle block: lines about as tall as the tallest line and vertically contiguous with it.
    /// Short text off to the side (button labels at the corners, the speaker's name tag) is dropped
    /// first: subtitles are centered or long, UI labels are short and off-center.
    static func subtitleBlock(_ all: [(String, CGRect)], centerX: CGFloat = 0.5, zoneWidth: CGFloat = 0.9) -> [CGRect] {
        let lines = all.filter { l in
            l.1.width >= zoneWidth * 0.3 || abs(l.1.midX - centerX) <= zoneWidth * 0.12
        }
        guard let main = lines.max(by: { $0.1.height < $1.1.height }) else { return [] }
        let h = main.1.height
        let sized = lines.map(\.1).filter { $0.height >= h * 0.7 }.sorted { $0.minY < $1.minY }
        guard let start = sized.firstIndex(of: main.1) else { return [main.1] }
        var block = [main.1]
        var i = start - 1
        while i >= 0, block[0].minY - sized[i].maxY < h * 0.9 { block.insert(sized[i], at: 0); i -= 1 }
        i = start + 1
        while i < sized.count, sized[i].minY - block.last!.maxY < h * 0.9 { block.append(sized[i]); i += 1 }
        return block
    }

    private static func result(_ obs: [(String, Float, CGRect)]) -> OcrResult {
        let text = joinLines(obs.map(\.0))
        let conf = obs.map(\.1).reduce(0, +) / Float(obs.count)
        let box = obs.dropFirst().reduce(obs[0].2) { $0.union($1.2) }
        let lineH = obs.map(\.2.height).sorted()[obs.count / 2] // median line
        return OcrResult(text: text, confidence: conf, bbox: box, language: detectLanguage(text), lineHeight: lineH)
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
