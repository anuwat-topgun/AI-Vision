import AVFoundation
import Combine
import QuartzCore

/// Translation adapter contract (README §4.2 TranslationProvider). Implementations must be
/// cancellable and must never block the main/render thread.
protocol SubtitleTranslator: AnyObject, Sendable {
    var modelId: String { get }
    /// `context`: recent (source, thai) pairs, oldest first, bounded by caller.
    func translate(_ text: String, sourceLanguage: String, context: [(String, String)]) async throws -> String
}

/// Live subtitle pipeline for one playing item (README §4.4):
/// video output → sampled OCR (latest frame only) → Rust stability tracker →
/// cache / single-flight translation → overlay, accepted only if epoch + subtitle still current.
@MainActor
final class SubtitlePipeline: ObservableObject {
    struct Overlay: Equatable {
        enum Status: Equatable { case translating, shown, failed(String) }
        var subtitleId: UInt64
        var sourceText: String
        var thai: String?
        var bbox: CGRect
        var status: Status
    }

    struct Debug: Equatable {
        var lastOcrText = ""
        var lastOcrConfidence: Float = 0
        var ocrMs = 0.0
        var translateMs = 0.0
        var staleDropped = 0
        var cacheHits = 0
        var translations = 0
    }

    @Published private(set) var overlay: Overlay?
    @Published private(set) var debug = Debug()
    @Published var enabled = true { didSet { if !enabled { invalidate() } } }
    @Published var hint: LanguageHint = .auto { didSet { ocr.hint = hint; invalidate() } }
    @Published private(set) var lastOcrBox: CGRect?
    var roi: CGRect { ocr.roi }

    /// OCR samples per second (§4.4 default 2–5).
    var sampleRate: Double = 4
    var translator: SubtitleTranslator?

    private var ocr = SubtitleOCR()
    private let tracker = SubtitleTracker(stableSamples: 2, missTolerance: 1, minConfidence: 0.4)
    private let ocrQueue = DispatchQueue(label: "aivision.ocr", qos: .userInitiated)
    private weak var frames: FrameSource?
    private var session: CoreSession?
    private var timer: Timer?
    private var ocrInFlight = false
    private var translateTask: Task<Void, Never>?
    private var cache: [String: String] = [:]
    private var context: [(String, String)] = []
    private var currentBox: [UInt64: CGRect] = [:]
    static let promptVersion = "p1"

    func attach(frames: FrameSource, session: CoreSession) {
        detach()
        self.frames = frames
        self.session = session
        context = []
        timer = Timer.scheduledTimer(withTimeInterval: 1 / sampleRate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func detach() {
        timer?.invalidate(); timer = nil
        frames = nil; session = nil
        invalidate()
    }

    /// Seek / hint change / disable: drop everything tied to the old position (AC-010, AC-011).
    func invalidate() {
        translateTask?.cancel(); translateTask = nil
        _ = tracker.reset()
        overlay = nil
        lastOcrBox = nil
        currentBox = [:]
    }

    private func tick() {
        guard enabled, !ocrInFlight, let frames, let session, let pb = frames.nextFrame() else { return }
        let tag = (session.sourceId(), session.epoch())
        ocrInFlight = true
        let ocr = self.ocr
        ocrQueue.async { [weak self] in
            let t0 = CACurrentMediaTime()
            let result = try? ocr.recognize(pb)
            let ms = (CACurrentMediaTime() - t0) * 1000
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handle(result, ocrMs: ms, tag: tag) }
            }
        }
    }

    /// Exposed for tests / BATCH_ANALYSIS: feed one OCR result as if sampled now.
    func handle(_ r: OcrResult?, ocrMs: Double, tag: (String, UInt64)) {
        ocrInFlight = false
        guard let session, session.isCurrent(sourceId: tag.0, epoch: tag.1) else {
            debug.staleDropped += 1; return
        }
        debug.ocrMs = ocrMs
        debug.lastOcrText = r?.text ?? ""
        debug.lastOcrConfidence = r?.confidence ?? 0
        lastOcrBox = r?.bbox
        for ev in tracker.observe(text: r?.text, confidence: r?.confidence ?? 0) {
            switch ev {
            case .vanished(let id):
                if overlay?.subtitleId == id { overlay = nil; translateTask?.cancel() }
                currentBox[id] = nil
            case .stable(let id, let text):
                let box = r?.bbox ?? .zero
                currentBox[id] = box
                startTranslation(id: id, text: text, language: r?.language ?? SubtitleOCR.detectLanguage(text),
                                 box: box, tag: tag)
            }
        }
        if let id = overlay?.subtitleId, let box = r?.bbox, tracker.currentId() == id {
            overlay?.bbox = box // follow small position changes
        }
    }

    private func cacheKey(_ text: String, _ lang: String) -> String {
        translationCacheKey(input: FfiCacheKeyInput(
            sourceLanguage: lang, targetLanguage: "th",
            modelId: translator?.modelId ?? "none", modelVersion: "1",
            promptTemplateVersion: Self.promptVersion, glossaryHash: "", normalizedText: text, contextHash: ""))
    }

    private func startTranslation(id: UInt64, text: String, language: String, box: CGRect, tag: (String, UInt64)) {
        translateTask?.cancel() // single-flight: only the current subtitle matters
        let key = cacheKey(text, language)
        if let hit = cache[key] {
            debug.cacheHits += 1
            overlay = Overlay(subtitleId: id, sourceText: text, thai: hit, bbox: box, status: .shown)
            return
        }
        guard let translator else {
            overlay = Overlay(subtitleId: id, sourceText: text, thai: nil, bbox: box,
                              status: .failed("No translation model loaded"))
            return
        }
        overlay = Overlay(subtitleId: id, sourceText: text, thai: nil, bbox: box, status: .translating)
        let ctx = Array(context.suffix(3))
        translateTask = Task { [weak self] in
            let t0 = CACurrentMediaTime()
            do {
                let thai = try await translator.translate(text, sourceLanguage: language, context: ctx)
                guard let self, !Task.isCancelled else { return }
                self.debug.translateMs = (CACurrentMediaTime() - t0) * 1000
                // Accept only if same source + epoch and the subtitle is still the visible one (§4.3).
                guard let s = self.session, s.isCurrent(sourceId: tag.0, epoch: tag.1),
                      self.tracker.currentId() == id else { self.debug.staleDropped += 1; return }
                self.cache[key] = thai
                self.context.append((text, thai)); if self.context.count > 10 { self.context.removeFirst() }
                self.debug.translations += 1
                self.overlay = Overlay(subtitleId: id, sourceText: text, thai: thai,
                                       bbox: self.currentBox[id] ?? box, status: .shown)
            } catch is CancellationError {
            } catch {
                guard let self, self.tracker.currentId() == id else { return }
                // Fallback: keep the original visible, no fabricated text (§6.5).
                self.overlay?.status = .failed(error.localizedDescription)
            }
        }
    }
}
