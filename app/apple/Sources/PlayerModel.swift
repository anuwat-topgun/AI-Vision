import AVFoundation
import Combine

/// File playback controller (E02, FR-001/FR-002). Picks a backend per file:
/// AVFoundation for MP4/MOV, VLC for MKV and anything AVFoundation rejects (ADR-0008).
/// Every seek or new file bumps the Rust session epoch (README §4.3, §10.3).
@MainActor
final class PlayerModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, ready, failed(String) }

    let pipeline = SubtitlePipeline()
    @Published private(set) var engine: PlaybackEngine?
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var epoch: UInt64 = 0
    @Published private(set) var videoSize: CGSize = .zero
    @Published var rate: Float = 1.0 { didSet { engine?.setRate(rate) } }
    @Published var volume: Float = 1.0 { didSet { applyVolume() } }
    @Published var isMuted = false { didSet { applyVolume() } }

    static let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    private(set) var session: CoreSession?
    private var clock: Timer?
    private var scopedURL: URL?

    var backendName: String { engine?.name ?? "—" }

    init() {
        clock = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let e = self.engine, self.state == .ready else { return }
                self.currentTime = e.currentTime
                self.isPlaying = e.isPlaying
            }
        }
    }

    /// Opens a user-selected file without copying it (README §10.1).
    func open(url: URL) async {
        close()
        state = .loading
        if url.startAccessingSecurityScopedResource() { scopedURL = url }
        let ext = url.pathExtension.lowercased()
        var candidates: [() -> PlaybackEngine] = [{ AVPlaybackEngine() }]
        #if os(macOS)
        if vlcOnlyExtensions.contains(ext) { candidates = [{ VLCPlaybackEngine() }] }
        else { candidates.append { VLCPlaybackEngine() } } // fallback for codecs AVFoundation lacks
        #endif
        var lastError: Error = EngineError.unsupported("no backend")
        for make in candidates {
            let e = make()
            do {
                let media = try await e.open(url: url)
                engine = e
                duration = media.duration
                videoSize = media.videoSize
                let s = CoreSession(sourceId: "file:\(UUID().uuidString)") // opaque id, never a path (§19.1(6))
                session = s
                epoch = s.epoch()
                applyVolume()
                pipeline.attach(frames: e.frames, session: s)
                state = .ready
                return
            } catch EngineError.protected {
                e.close(); lastError = EngineError.protected; break // never try to bypass DRM
            } catch {
                e.close(); lastError = error
            }
        }
        fail(lastError.localizedDescription)
    }

    func togglePlay() {
        guard let e = engine else { return }
        if e.isPlaying { e.pause() } else { e.play(rate: rate) }
        isPlaying = !isPlaying
    }

    @discardableResult
    func skip(_ seconds: Double) async -> Bool { await seek(to: currentTime + seconds) }

    /// Seek invalidates all in-flight AI work for the old position (AC-010).
    /// Returns false if the seek was interrupted by a newer seek.
    @discardableResult
    func seek(to seconds: Double) async -> Bool {
        guard let e = engine else { return false }
        let target = min(max(0, seconds), duration)
        if let s = session { epoch = s.bump(reason: .seek) }
        pipeline.invalidate() // clear stale overlay before the new frame shows
        let finished = await e.seek(to: target)
        currentTime = e.currentTime
        return finished
    }

    func close() {
        pipeline.detach()
        engine?.close()
        engine = nil
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        session = nil
        currentTime = 0; duration = 0; isPlaying = false; videoSize = .zero
        state = .idle
    }

    private func applyVolume() { engine?.setVolume(volume, muted: isMuted) }

    private func fail(_ message: String) {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        state = .failed(message)
    }

    static func format(_ s: Double) -> String {
        let total = Int(s.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
