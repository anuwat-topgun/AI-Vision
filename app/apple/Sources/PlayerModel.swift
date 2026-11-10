import AVFoundation
import Combine

/// File playback controller (E02, FR-001/FR-002, AC-001/AC-002).
/// Video renders through AVPlayerLayer; frames never cross into Rust or SwiftUI state.
/// Every seek or new file bumps the Rust session epoch (README §4.3, §10.3).
@MainActor
final class PlayerModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, ready, failed(String) }

    let player = AVPlayer()
    let pipeline = SubtitlePipeline()
    @Published private(set) var videoSize: CGSize = .zero
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var epoch: UInt64 = 0
    @Published var rate: Float = 1.0 { didSet { if isPlaying { player.rate = rate } } }
    @Published var volume: Float = 1.0 { didSet { player.volume = volume } }
    @Published var isMuted = false { didSet { player.isMuted = isMuted } }

    static let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    private(set) var session: CoreSession?
    private var timeObserver: Any?
    private var scopedURL: URL?

    init() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 10), queue: .main
        ) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = t.seconds.isFinite ? t.seconds : 0
                self.isPlaying = self.player.rate != 0
            }
        }
    }

    /// Opens a user-selected file. Accepts security-scoped URLs from the document picker
    /// without copying the file (README §10.1).
    func open(url: URL) async {
        close()
        state = .loading
        if url.startAccessingSecurityScopedResource() { scopedURL = url }
        let asset = AVURLAsset(url: url)
        do {
            let (playable, protected, dur) = try await asset.load(.isPlayable, .hasProtectedContent, .duration)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            if protected {
                return fail("This file is DRM-protected and can't be played.")
            }
            guard playable, !videoTracks.isEmpty else {
                return fail("Unsupported file: this device can't decode its video format.")
            }
            duration = dur.seconds.isFinite ? dur.seconds : 0
            let item = AVPlayerItem(asset: asset)
            player.replaceCurrentItem(with: item)
            guard await Self.waitUntilReady(item) else {
                return fail("Unsupported file: \(item.error?.localizedDescription ?? "decoder failed")")
            }
            // Source identity is opaque to core; never persist a raw path as identity (§19.1(6)).
            let s = CoreSession(sourceId: "file:\(UUID().uuidString)")
            session = s
            epoch = s.epoch()
            if let track = videoTracks.first {
                let (size, t) = try await track.load(.naturalSize, .preferredTransform)
                let r = size.applying(t)
                videoSize = CGSize(width: abs(r.width), height: abs(r.height))
            }
            pipeline.attach(item: item, session: s)
            state = .ready
        } catch {
            fail("Couldn't open the file: \(error.localizedDescription)")
        }
    }

    func togglePlay() {
        if isPlaying { player.pause() } else { player.rate = rate }
        isPlaying = player.rate != 0
    }

    @discardableResult
    func skip(_ seconds: Double) async -> Bool { await seek(to: currentTime + seconds) }

    /// Seek invalidates all in-flight AI work for the old position (AC-010).
    /// Returns false if the seek was interrupted by a newer seek.
    @discardableResult
    func seek(to seconds: Double) async -> Bool {
        let target = min(max(0, seconds), duration)
        if let s = session { epoch = s.bump(reason: .seek) }
        pipeline.invalidate() // clear stale overlay before the new frame shows (AC-010)
        let t = CMTime(seconds: target, preferredTimescale: 600)
        let finished = await player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = player.currentTime().seconds
        return finished
    }

    func close() {
        pipeline.detach()
        player.pause()
        player.replaceCurrentItem(with: nil)
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        session = nil
        currentTime = 0; duration = 0; isPlaying = false
        state = .idle
    }

    private func fail(_ message: String) {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        state = .failed(message)
    }

    /// Seeking or presenting before `.readyToPlay` silently does nothing, so wait for it.
    private static func waitUntilReady(_ item: AVPlayerItem, timeout: Double = 10) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            switch item.status {
            case .readyToPlay: return true
            case .failed: return false
            default: try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        return false
    }

    static func format(_ s: Double) -> String {
        let total = Int(s.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
