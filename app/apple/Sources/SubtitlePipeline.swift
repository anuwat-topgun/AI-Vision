import AVFoundation
import Combine
import QuartzCore

/// Translation adapter contract (README §4.2 TranslationProvider). Implementations must be
/// cancellable and must never block the main/render thread.
protocol SubtitleTranslator: AnyObject, Sendable {
    var modelId: String { get }
    var modelRevision: String { get }
    var quantizationId: String { get }
    var promptVersion: String { get }
    func translate(_ request: TranslationRequest) async throws -> TranslationOutcome
}

struct TranslationRequest {
    var sourceText: String
    var language: FfiSourceLanguage
    /// Successful pairs from this session only (§4.2).
    var history: [FfiHistoryPair]
}

/// Typed result at the renderer boundary (§6.2). Only `.translated` may render or mask.
enum TranslationOutcome: Equatable {
    case translated(String)
    case unreadable
    case invalid(String)
}

extension FfiSourceLanguage {
    init(code: String) { self = code == "ja" ? .japanese : .english }
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
        var unreadable = 0
        var invalid = 0
        var cacheHits = 0
        var translations = 0
    }

    @Published private(set) var overlay: Overlay?
    @Published private(set) var debug = Debug()
    @Published var enabled = true { didSet { if !enabled { invalidate() } } }
    @Published var hint: LanguageHint = .auto { didSet { ocr.hint = hint; invalidate() } }
    @Published private(set) var lastOcrBox: CGRect?
    /// Average colour around the source text (RGB 0–1), for Mask & Replace.
    @Published private(set) var background: SIMD3<Float>?
    /// Source line height (normalized) of the current subtitle.
    @Published private(set) var lineHeight: CGFloat?
    /// OCR zone, normalized top-left origin. Only text inside it is read and translated.
    @Published var roi = SubtitleOCR.defaultRoi { didSet { ocr.roi = roi; invalidate() } }

    /// OCR samples per second (§4.4 default 2–5).
    var sampleRate: Double = 4
    var translator: SubtitleTranslator?

    private var ocr = SubtitleOCR()
    private let tracker = SubtitleTracker(stableSamples: 2, missTolerance: 2, minConfidence: 0.4)
    private let ocrQueue = DispatchQueue(label: "aivision.ocr", qos: .userInitiated)
    private var frames: FrameSource? // strong: per-zone taps are owned here
    private var session: CoreSession?
    private var timer: Timer?
    private var ocrInFlight = false
    private var translateTask: Task<Void, Never>?
    private var cache: [String: String] = [:]
    /// Session-scoped history: cleared on new file, seek and language change (§4.2, TR-P2-017).
    private let history = TranslationHistory()
    private var currentBox: [UInt64: CGRect] = [:]
    private var hideTask: Task<Void, Never>?
    /// Seconds the Thai stays after the source subtitle disappears.
    static var holdAfterVanish = 0.8

    func attach(frames: FrameSource, session: CoreSession) {
        detach()
        self.frames = frames
        self.session = session
        history.clear()
        cache = [:]
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
        hideTask?.cancel(); hideTask = nil
        history.clear()
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
        if let bg = r?.background { background = bg }
        if let lh = r?.lineHeight { lineHeight = lh }
        for ev in tracker.observe(text: r?.text, confidence: r?.confidence ?? 0) {
            switch ev {
            case .vanished(let id):
                if overlay?.subtitleId == id {
                    translateTask?.cancel()
                    // Hold the Thai a moment so it doesn't blink off between text frames.
                    hideTask?.cancel()
                    hideTask = Task { [weak self] in
                        try? await Task.sleep(for: .milliseconds(Int(Self.holdAfterVanish * 1000)))
                        guard !Task.isCancelled, let self, self.overlay?.subtitleId == id else { return }
                        self.overlay = nil
                    }
                }
                currentBox[id] = nil
            case .stable(let id, let text):
                hideTask?.cancel()
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

    private func cacheKey(_ text: String, _ lang: FfiSourceLanguage) -> String? {
        guard let t = translator else { return nil }
        let normalized: String
        switch sanitizeSubtitle(input: text) {
        case .ok(let clean, _): normalized = clean
        case .reject: return nil
        }
        return translationCacheId(i: FfiCacheIdentity(
            modelId: t.modelId, modelRevision: t.modelRevision, quantizationId: t.quantizationId,
            promptVersion: t.promptVersion, decodingId: decodingId(), sourceLanguage: lang,
            normalizedText: normalized, historyFingerprint: history.fingerprint(),
            gameProfileId: nil, glossaryVersion: nil))
    }

    private func startTranslation(id: UInt64, text: String, language: String, box: CGRect, tag: (String, UInt64)) {
        translateTask?.cancel() // single-flight: only the current subtitle matters
        let lang = FfiSourceLanguage(code: language)
        let key = cacheKey(text, lang)
        if let key, let hit = cache[key] {
            debug.cacheHits += 1
            overlay = Overlay(subtitleId: id, sourceText: text, thai: hit, bbox: box, status: .shown)
            history.push(language: lang, source: text, thai: hit)
            return
        }
        guard let translator else {
            overlay = Overlay(subtitleId: id, sourceText: text, thai: nil, bbox: box,
                              status: .failed("No translation model loaded — choose one with the cpu button"))
            return
        }
        if overlay?.status == .shown {
            overlay?.subtitleId = id // previous Thai stays until the new one is ready (no blink)
        } else {
            overlay = Overlay(subtitleId: id, sourceText: text, thai: nil, bbox: box, status: .translating)
        }
        let request = TranslationRequest(sourceText: text, language: lang, history: history.pairs())
        translateTask = Task { [weak self] in
            let t0 = CACurrentMediaTime()
            do {
                let outcome = try await translator.translate(request)
                guard let self, !Task.isCancelled else { return }
                self.debug.translateMs = (CACurrentMediaTime() - t0) * 1000
                // Accept only if same source + epoch and the subtitle is still the visible one (§4.3, §6.3).
                guard let s = self.session, s.isCurrent(sourceId: tag.0, epoch: tag.1),
                      self.tracker.currentId() == id else { self.debug.staleDropped += 1; return }
                switch outcome {
                case .translated(let thai):
                    if let key { self.cache[key] = thai } // cache only validated successes (§8)
                    self.history.push(language: lang, source: text, thai: thai)
                    self.debug.translations += 1
                    self.overlay = Overlay(subtitleId: id, sourceText: text, thai: thai,
                                           bbox: self.currentBox[id] ?? box, status: .shown)
                case .unreadable:
                    self.debug.unreadable += 1
                    self.overlay = nil // no "???", no mask: original stays visible (§6.2)
                case .invalid(let why):
                    self.debug.invalid += 1
                    self.overlay = Overlay(subtitleId: id, sourceText: text, thai: nil, bbox: box,
                                           status: .failed("invalid output: \(why)")) // shown only in Debug
                }
            } catch is CancellationError {
            } catch {
                guard let self, self.tracker.currentId() == id else { return }
                self.overlay?.status = .failed(error.localizedDescription) // never render Thai on error
            }
        }
    }

}
