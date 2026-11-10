#if os(macOS)
import AVFoundation
import CoreMedia
import QuartzCore

/// VLC backend (libvlc 3 via VLCKit) for MKV and other containers (ADR-0008).
/// libvlc decodes into our IOSurface-backed BGRA CVPixelBuffers; the same buffer is shown in an
/// AVSampleBufferDisplayLayer and offered to OCR. Audio is played by VLC itself.
@MainActor
final class VLCPlaybackEngine: PlaybackEngine {
    let name = "VLC"
    private let display = AVSampleBufferDisplayLayer()
    var videoLayer: CALayer { display }
    var frames: FrameSource { sink }
    private let sink = VLCFrameSink()
    private var instance: OpaquePointer?
    private var mp: OpaquePointer?
    private var lengthMs: Int64 = 0

    init() {
        display.videoGravity = .resizeAspect
        display.backgroundColor = CGColor(gray: 0, alpha: 1)
        sink.layer = display
    }

    var currentTime: Double {
        guard let mp else { return 0 }
        return Double(max(0, libvlc_media_player_get_time(mp))) / 1000
    }
    var isPlaying: Bool { mp.map { libvlc_media_player_is_playing($0) != 0 } ?? false }

    func open(url: URL) async throws -> OpenedMedia {
        close()
        let args = ["--no-video-title-show", "--no-snapshot-preview", "--no-osd", "--no-sub-autodetect-file"]
        var cargs = args.map { UnsafePointer<CChar>(strdup($0)) }
        defer { cargs.forEach { free(UnsafeMutablePointer(mutating: $0)) } }
        guard let inst = libvlc_new(Int32(cargs.count), &cargs) else {
            throw EngineError.unsupported("VLC failed to start")
        }
        instance = inst
        guard let media = libvlc_media_new_path(inst, url.path) else {
            throw EngineError.unsupported("VLC can't open this file")
        }
        defer { libvlc_media_release(media) }
        // Parse first: fail fast on non-media, and learn the visible video size (decoders pad to 16 px).
        guard let visible = await Self.parseVideoSize(media) else {
            close(); throw EngineError.unsupported("no playable video stream (VLC).")
        }
        let player = libvlc_media_player_new_from_media(media)!
        mp = player
        sink.reset(visible: visible)
        let opaque = Unmanaged.passUnretained(sink).toOpaque()
        libvlc_video_set_callbacks(player, vlcLock, vlcUnlock, vlcDisplay, opaque)
        libvlc_video_set_format_callbacks(player, vlcFormat, vlcCleanup)
        libvlc_media_player_play(player)

        // Wait for first decoded frame (or error) — bounded.
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let st = libvlc_media_player_get_state(player)
            if st == libvlc_Error || st == libvlc_Ended { close(); throw EngineError.unsupported("VLC couldn't decode this file.") }
            if sink.framesDisplayed > 0 { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        guard sink.framesDisplayed > 0 else {
            close(); throw EngineError.unsupported("no video stream found.")
        }
        libvlc_media_player_set_pause(player, 1)
        _ = await seek(to: 0)
        lengthMs = libvlc_media_player_get_length(player)
        return OpenedMedia(duration: Double(max(0, lengthMs)) / 1000, videoSize: sink.size)
    }

    private static func parseVideoSize(_ media: OpaquePointer) async -> CGSize? {
        libvlc_media_parse_with_options(media, libvlc_media_parse_local, 5000)
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            let st = libvlc_media_get_parsed_status(media)
            if st == libvlc_media_parsed_status_done { break }
            if st == libvlc_media_parsed_status_failed || st == libvlc_media_parsed_status_timeout { return nil }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        var tracks: UnsafeMutablePointer<UnsafeMutablePointer<libvlc_media_track_t>?>?
        let n = libvlc_media_tracks_get(media, &tracks)
        defer { if let tracks { libvlc_media_tracks_release(tracks, n) } }
        guard let tracks else { return nil }
        for i in 0..<Int(n) {
            guard let t = tracks[i], t.pointee.i_type == libvlc_track_video, let v = t.pointee.video,
                  v.pointee.i_width > 0, v.pointee.i_height > 0 else { continue }
            return CGSize(width: Int(v.pointee.i_width), height: Int(v.pointee.i_height))
        }
        return nil
    }

    func play(rate: Float) {
        guard let mp else { return }
        libvlc_media_player_set_rate(mp, rate)
        libvlc_media_player_set_pause(mp, 0)
    }
    func pause() { if let mp { libvlc_media_player_set_pause(mp, 1) } }
    func setRate(_ r: Float) { if let mp { libvlc_media_player_set_rate(mp, r) } }
    func setVolume(_ v: Float, muted: Bool) {
        guard let mp else { return }
        libvlc_audio_set_volume(mp, Int32(v * 100))
        libvlc_audio_set_mute(mp, muted ? 1 : 0)
    }

    /// libvlc seeks asynchronously; wait until the clock lands near the target (bounded).
    func seek(to seconds: Double) async -> Bool {
        guard let mp else { return false }
        let target = Int64(seconds * 1000)
        let before = sink.framesDisplayed
        libvlc_media_player_set_time(mp, target)
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if abs(libvlc_media_player_get_time(mp) - target) <= 50, sink.framesDisplayed > before || !isPlaying {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return abs(libvlc_media_player_get_time(mp) - target) <= 250
    }

    func close() {
        if let mp {
            libvlc_media_player_stop(mp) // blocks until decoder threads end; callbacks stop
            libvlc_media_player_release(mp)
        }
        mp = nil
        if let instance { libvlc_release(instance) }
        instance = nil
        display.flushAndRemoveImage()
    }
}

/// Receives frames on VLC's decoder thread. Thread-safe; owns the CVPixelBuffer pool.
final class VLCFrameSink: FrameSource, @unchecked Sendable {
    weak var layer: AVSampleBufferDisplayLayer?
    private let lock = NSLock()
    private var pool: CVPixelBufferPool?
    private var latest: CVPixelBuffer?
    private var latestTaken = true
    private(set) var size: CGSize = .zero
    private var displayed = 0
    /// Buffers handed to VLC and not yet displayed. VLC may drop pictures without calling
    /// display, so keep this bounded and release the oldest (no leak during long sessions).
    private var inflight: [UnsafeMutableRawPointer] = []
    var framesDisplayed: Int { lock.lock(); defer { lock.unlock() }; return displayed }

    private var visible: CGSize = .zero

    func reset(visible: CGSize) {
        lock.lock()
        let old = inflight; inflight = []
        latest = nil; latestTaken = true; displayed = 0; self.visible = visible
        lock.unlock()
        old.forEach { Unmanaged<CVPixelBuffer>.fromOpaque($0).release() }
    }

    deinit { inflight.forEach { Unmanaged<CVPixelBuffer>.fromOpaque($0).release() } }

    /// VLC writes `width`×`height` (coded, e.g. 1920×1088). Buffers report the visible size and
    /// treat the rest as extended (padding) pixels, so display and OCR see 1920×1080.
    func configure(width: Int, height: Int) {
        lock.lock(); let vis = visible; lock.unlock()
        let vw = vis.width > 0 && Int(vis.width) <= width ? Int(vis.width) : width
        let vh = vis.height > 0 && Int(vis.height) <= height ? Int(vis.height) : height
        var p: CVPixelBufferPool?
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: vw, kCVPixelBufferHeightKey as String: vh,
            kCVPixelBufferExtendedPixelsRightKey as String: width - vw,
            kCVPixelBufferExtendedPixelsBottomKey as String: height - vh,
            kCVPixelBufferBytesPerRowAlignmentKey as String: 64,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        CVPixelBufferPoolCreate(nil, [kCVPixelBufferPoolMinimumBufferCountKey: 4] as CFDictionary, attrs as CFDictionary, &p)
        lock.lock(); pool = p; size = CGSize(width: vw, height: vh); lock.unlock()
    }

    /// Row stride VLC must use; read from a real buffer so it matches CoreVideo's layout.
    func bytesPerRow() -> Int {
        lock.lock(); let pool = self.pool; lock.unlock()
        var pb: CVPixelBuffer?
        guard let pool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) == kCVReturnSuccess, let pb else { return 0 }
        return CVPixelBufferGetBytesPerRow(pb)
    }

    func lockBuffer(_ planes: UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> UnsafeMutableRawPointer? {
        lock.lock(); let pool = self.pool; lock.unlock()
        var pb: CVPixelBuffer?
        guard let pool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) == kCVReturnSuccess, let pb else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        planes[0] = CVPixelBufferGetBaseAddress(pb)
        let ptr = Unmanaged.passRetained(pb).toOpaque() // released in display() or evicted below
        lock.lock()
        inflight.append(ptr)
        let evict = inflight.count > 16 ? inflight.removeFirst() : nil
        lock.unlock()
        if let evict { Unmanaged<CVPixelBuffer>.fromOpaque(evict).release() }
        return ptr
    }

    func unlockBuffer(_ picture: UnsafeMutableRawPointer?) {
        guard let picture else { return }
        let pb = Unmanaged<CVPixelBuffer>.fromOpaque(picture).takeUnretainedValue()
        CVPixelBufferUnlockBaseAddress(pb, [])
    }

    func display(_ picture: UnsafeMutableRawPointer?) {
        guard let picture else { return }
        lock.lock()
        guard let i = inflight.firstIndex(of: picture) else { lock.unlock(); return } // already evicted
        inflight.remove(at: i)
        let pb = Unmanaged<CVPixelBuffer>.fromOpaque(picture).takeRetainedValue()
        latest = pb; latestTaken = false; displayed += 1
        lock.unlock()
        var fmt: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pb, formatDescriptionOut: &fmt)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sb: CMSampleBuffer?
        guard let fmt, CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pb, formatDescription: fmt,
                                                                 sampleTiming: &timing, sampleBufferOut: &sb) == noErr,
              let sb else { return }
        if let att = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true) as? [NSMutableDictionary] {
            att.first?[kCMSampleAttachmentKey_DisplayImmediately] = true
        }
        DispatchQueue.main.async { [weak self] in
            guard let layer = self?.layer else { return }
            if layer.status == .failed { layer.flush() }
            layer.enqueue(sb)
        }
    }

    func nextFrame() -> CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        guard !latestTaken else { return nil }
        latestTaken = true
        return latest
    }
}

// C callbacks (no captures allowed): route to the sink passed as `opaque`.
private func sink(_ p: UnsafeMutableRawPointer?) -> VLCFrameSink {
    Unmanaged<VLCFrameSink>.fromOpaque(p!).takeUnretainedValue()
}
private let vlcFormat: libvlc_video_format_cb = { opaque, chroma, width, height, pitches, lines in
    guard let opaque, let chroma, let width, let height, let pitches, let lines else { return 0 }
    let w = Int(width.pointee), h = Int(height.pointee)
    "BGRA".withCString { strncpy(chroma, $0, 4) }
    let s = sink(opaque.pointee)
    s.configure(width: w, height: h)
    let bpr = s.bytesPerRow()
    guard bpr >= w * 4 else { return 0 }
    pitches[0] = UInt32(bpr)
    lines[0] = UInt32(h)
    return 1
}
private let vlcCleanup: libvlc_video_cleanup_cb = { _ in }
private let vlcLock: libvlc_video_lock_cb = { opaque, planes in
    guard let planes else { return nil }
    return sink(opaque).lockBuffer(planes)
}
private let vlcUnlock: libvlc_video_unlock_cb = { opaque, picture, _ in sink(opaque).unlockBuffer(picture) }
private let vlcDisplay: libvlc_video_display_cb = { opaque, picture in sink(opaque).display(picture) }
#endif
