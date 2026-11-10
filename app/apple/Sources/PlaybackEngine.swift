import AVFoundation
import QuartzCore

/// Latest decoded video frame for analysis (OCR). Must never block the render path.
protocol FrameSource: AnyObject {
    /// Returns a frame newer than the last one returned, or nil.
    func nextFrame() -> CVPixelBuffer?
}

struct OpenedMedia {
    var duration: Double
    var videoSize: CGSize
}

enum EngineError: LocalizedError {
    case unsupported(String), protected
    var errorDescription: String? {
        switch self {
        case .unsupported(let why): "Unsupported file: \(why)"
        case .protected: "This file is DRM-protected and can't be played."
        }
    }
}

/// One playback backend (README §5.1 FileInputProvider). AVFoundation for MP4/MOV;
/// VLC for MKV and containers AVFoundation can't open (ADR-0008).
@MainActor
protocol PlaybackEngine: AnyObject {
    var name: String { get }
    /// Native video layer: frames go straight to the compositor, never through SwiftUI state.
    var videoLayer: CALayer { get }
    var frames: FrameSource { get }
    var currentTime: Double { get }
    var isPlaying: Bool { get }
    func open(url: URL) async throws -> OpenedMedia
    func play(rate: Float)
    func pause()
    /// Exact seek; returns false if superseded.
    func seek(to seconds: Double) async -> Bool
    func setVolume(_ v: Float, muted: Bool)
    func setRate(_ r: Float)
    func close()
}

// MARK: - AVFoundation

@MainActor
final class AVPlaybackEngine: PlaybackEngine, FrameSource {
    let name = "AVFoundation"
    let player = AVPlayer()
    private let layer = AVPlayerLayer()
    private var output: AVPlayerItemVideoOutput?
    var videoLayer: CALayer { layer }
    var frames: FrameSource { self }

    init() {
        layer.player = player
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = CGColor(gray: 0, alpha: 1)
    }

    var currentTime: Double { let t = player.currentTime().seconds; return t.isFinite ? t : 0 }
    var isPlaying: Bool { player.rate != 0 }

    func open(url: URL) async throws -> OpenedMedia {
        let asset = AVURLAsset(url: url)
        let (playable, protected, dur) = try await asset.load(.isPlayable, .hasProtectedContent, .duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        if protected { throw EngineError.protected }
        guard playable, let track = videoTracks.first else {
            throw EngineError.unsupported("this device can't decode its video format.")
        }
        let (size, t) = try await track.load(.naturalSize, .preferredTransform)
        let r = size.applying(t)
        let item = AVPlayerItem(asset: asset)
        let out = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ])
        item.add(out)
        output = out
        player.replaceCurrentItem(with: item)
        guard await Self.waitUntilReady(item) else {
            throw EngineError.unsupported(item.error?.localizedDescription ?? "decoder failed")
        }
        return OpenedMedia(duration: dur.seconds.isFinite ? dur.seconds : 0,
                           videoSize: CGSize(width: abs(r.width), height: abs(r.height)))
    }

    func nextFrame() -> CVPixelBuffer? {
        guard let output else { return nil }
        let t = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: t) else { return nil }
        return output.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: nil)
    }

    func play(rate: Float) { player.rate = rate }
    func pause() { player.pause() }
    func setRate(_ r: Float) { if isPlaying { player.rate = r } }
    func setVolume(_ v: Float, muted: Bool) { player.volume = v; player.isMuted = muted }

    func seek(to seconds: Double) async -> Bool {
        await player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                          toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func close() {
        player.pause()
        if let o = output { player.currentItem?.remove(o) }
        output = nil
        player.replaceCurrentItem(with: nil)
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
}

/// Containers AVFoundation never opens; go straight to VLC where available.
let vlcOnlyExtensions: Set<String> = ["mkv", "webm", "avi", "flv", "ts", "m2ts", "ogv", "wmv"]
