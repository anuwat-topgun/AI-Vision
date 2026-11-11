import AVFoundation
import Combine
import CoreMedia

/// One selectable capture format (README §5.2). Pure data so selection logic is unit-testable.
struct CaptureFormatOption: Identifiable, Hashable {
    var id: String { "\(width)x\(height)@\(Int(maxFps))-\(pixelFormat)" }
    let width: Int
    let height: Int
    let maxFps: Double
    let pixelFormat: String // fourcc, e.g. "420v", "yuvs", "dmb1" (MJPEG)
    let index: Int          // index into device.formats
    var label: String { "\(width)×\(height) @ \(Int(maxFps.rounded())) fps · \(pixelFormat)" }

    /// §5.2: prefer 1080p60 SDR, then 1080p30, 720p60, 720p30; else the largest ≤1080p; uncompressed over MJPEG.
    static func preferred(_ options: [CaptureFormatOption]) -> CaptureFormatOption? {
        let ladder: [(Int, Int, Double)] = [(1920, 1080, 59), (1920, 1080, 29), (1280, 720, 59), (1280, 720, 29)]
        let rank: (CaptureFormatOption) -> Int = { $0.pixelFormat == "dmb1" || $0.pixelFormat == "jpeg" ? 1 : 0 }
        for (w, h, fps) in ladder {
            let m = options.filter { $0.width == w && $0.height == h && $0.maxFps >= fps }
            if let best = m.min(by: { (rank($0), -$0.maxFps) < (rank($1), -$1.maxFps) }) { return best }
        }
        return options.filter { $0.height <= 1080 }
            .max { ($0.width * $0.height, $0.maxFps) < ($1.width * $1.height, $1.maxFps) } ?? options.first
    }
}

struct CaptureDeviceInfo: Identifiable, Hashable {
    let id: String   // AVCaptureDevice.uniqueID (opaque; never persisted as cross-platform identity)
    let name: String
    let model: String
}

/// Live UVC capture (E07 macOS; same AVFoundation path serves iPadOS external devices, E06).
/// Preview via AVCaptureVideoPreviewLayer (native, no copies); frames for OCR via a
/// latest-frame-only data output (README §4.4 bounded queue).
@MainActor
final class LiveCaptureEngine: NSObject, ObservableObject {
    enum State: Equatable {
        case idle, permissionDenied, starting, running
        case disconnected(String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var devices: [CaptureDeviceInfo] = []
    @Published private(set) var audioDevices: [CaptureDeviceInfo] = []
    @Published private(set) var formats: [CaptureFormatOption] = []
    @Published private(set) var activeFormat: CaptureFormatOption?
    @Published private(set) var measuredFps: Double = 0
    @Published private(set) var droppedFrames = 0
    @Published private(set) var epoch: UInt64 = 0
    @Published var audioEnabled = false { didSet { applyAudio() } }
    @Published var volume: Float = 1 { didSet { applyAudio() } }

    let session = AVCaptureSession()
    let previewLayer: AVCaptureVideoPreviewLayer
    /// One pipeline per subtitle zone; zone 0 is the main dialogue zone.
    @Published private(set) var pipelines = [SubtitlePipeline()]
    var pipeline: SubtitlePipeline { pipelines[0] }
    private(set) var coreSession: CoreSession?

    /// Replace the zone list (normalized rects). Keeps the main pipeline's settings on new zones.
    private var profile: GameProfile?

    func setProfile(_ p: GameProfile?) {
        profile = p
        pipelines.forEach { $0.profile = p }
    }

    func setZones(_ rois: [CGRect], roles: [ZoneRole] = []) {
        let rois = rois.isEmpty ? [SubtitleOCR.defaultRoi] : rois
        while pipelines.count < rois.count {
            let p = SubtitlePipeline()
            p.translator = pipeline.translator; p.hint = pipeline.hint; p.enabled = pipeline.enabled
            p.profile = profile
            if state == .running, let cs = coreSession { p.attach(frames: sink.tap(), session: cs) }
            pipelines.append(p)
        }
        while pipelines.count > rois.count { pipelines.removeLast().detach() }
        for (p, r) in zip(pipelines, rois) where p.roi != r { p.roi = r }
        for (i, p) in pipelines.enumerated() {
            let role = i > 0 && i < roles.count ? roles[i] : .translate
            if p.translates != (role == .translate) { p.translates = role == .translate; p.invalidate() }
        }
        // Translating zones read the speaker from the first speaker-name zone.
        let speakerZone = pipelines.first { !$0.translates }
        for p in pipelines where p.translates {
            p.speakerSource = { [weak speakerZone] in speakerZone?.speakerText }
        }
    }
    private let sink = CaptureFrameSink()
    private let videoQueue = DispatchQueue(label: "aivision.capture.video", qos: .userInteractive)
    private var selectedDevice: AVCaptureDevice?
    private var audioInput: AVCaptureDeviceInput?
    #if os(macOS)
    private let audioPreview = AVCaptureAudioPreviewOutput()
    #endif
    private var observers: [NSObjectProtocol] = []
    private var fpsTimer: Timer?

    override init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init()
        previewLayer.videoGravity = .resizeAspect
        previewLayer.backgroundColor = CGColor(gray: 0, alpha: 1)
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main) { [weak self] n in
            MainActor.assumeIsolated { self?.deviceDisconnected(n.object as? AVCaptureDevice) }
        })
        observers.append(nc.addObserver(forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: .main) { [weak self] n in
            MainActor.assumeIsolated { self?.deviceConnected(n.object as? AVCaptureDevice) }
        })
        observers.append(nc.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] n in
            let err = n.userInfo?[AVCaptureSessionErrorKey] as? Error
            MainActor.assumeIsolated { self?.fail("Capture error: \(err?.localizedDescription ?? "unknown")") }
        })
        refreshDevices()
    }

    // MARK: Discovery

    static var videoDeviceTypes: [AVCaptureDevice.DeviceType] {
        // .external = UVC capture cards and USB cameras (macOS 14+/iPadOS 17+). No Continuity/built-in by default.
        [.external]
    }

    func refreshDevices() {
        let v = AVCaptureDevice.DiscoverySession(deviceTypes: Self.videoDeviceTypes, mediaType: .video, position: .unspecified)
        devices = v.devices.map { CaptureDeviceInfo(id: $0.uniqueID, name: $0.localizedName, model: $0.modelID) }
        #if os(macOS)
        let a = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
        audioDevices = a.devices.map { CaptureDeviceInfo(id: $0.uniqueID, name: $0.localizedName, model: $0.modelID) }
        #endif
    }

    func select(deviceId: String) {
        guard let d = AVCaptureDevice(uniqueID: deviceId) else { formats = []; return }
        selectedDevice = d
        formats = d.formats.enumerated().compactMap { i, f in
            let dims = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            let fps = f.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            let fourcc = Self.fourcc(CMFormatDescriptionGetMediaSubType(f.formatDescription))
            return CaptureFormatOption(width: Int(dims.width), height: Int(dims.height), maxFps: fps, pixelFormat: fourcc, index: i)
        }
        // Collapse duplicates (same size/fps/fourcc), sorted largest first.
        var seen = Set<String>()
        formats = formats.filter { seen.insert($0.id).inserted }
            .sorted { ($0.height, $0.maxFps) > ($1.height, $1.maxFps) }
    }

    nonisolated static func fourcc(_ code: FourCharCode) -> String {
        let chars = [24, 16, 8, 0].map { Character(UnicodeScalar(UInt8((code >> $0) & 0xFF))) }
        return String(chars).trimmingCharacters(in: .whitespaces)
    }

    // MARK: Session

    func start(deviceId: String, format: CaptureFormatOption?, audioDeviceId: String?) async {
        stop()
        state = .starting
        guard await Self.requestAccess(.video) else { state = .permissionDenied; return }
        select(deviceId: deviceId)
        guard let device = selectedDevice else { return fail("Device not found — reconnect it and refresh.") }
        let chosen = format ?? CaptureFormatOption.preferred(formats)

        session.beginConfiguration()
        #if os(iOS)
        session.sessionPreset = .inputPriority // use the device format we set, not a preset
        #endif // macOS: setting device.activeFormat overrides the session preset
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { session.commitConfiguration(); return fail("This device can't be used for capture.") }
            session.addInput(input)
            if let chosen {
                try device.lockForConfiguration()
                device.activeFormat = device.formats[chosen.index]
                // Run at ≤60 fps: the pipeline targets 60 (README §5.2); higher rates only cost CPU/USB.
                let ranges = device.activeFormat.videoSupportedFrameRateRanges
                if ranges.contains(where: { $0.minFrameRate <= 60 && $0.maxFrameRate >= 60 }) {
                    device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60)
                } else if let r = ranges.filter({ $0.maxFrameRate <= 60 }).max(by: { $0.maxFrameRate < $1.maxFrameRate }) {
                    device.activeVideoMinFrameDuration = r.minFrameDuration
                } else if let r = ranges.min(by: { $0.maxFrameRate < $1.maxFrameRate }) {
                    device.activeVideoMinFrameDuration = r.minFrameDuration
                }
                device.unlockForConfiguration()
            }
            let out = AVCaptureVideoDataOutput()
            out.alwaysDiscardsLateVideoFrames = true // latest frame only; never queue for OCR
            out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            out.setSampleBufferDelegate(sink, queue: videoQueue)
            guard session.canAddOutput(out) else { session.commitConfiguration(); return fail("Can't read frames from this device.") }
            session.addOutput(out)
            if let aid = audioDeviceId, let ad = AVCaptureDevice(uniqueID: aid), await Self.requestAccess(.audio) {
                let ai = try AVCaptureDeviceInput(device: ad)
                if session.canAddInput(ai) { session.addInput(ai); audioInput = ai }
                #if os(macOS)
                if session.canAddOutput(audioPreview) { session.addOutput(audioPreview) }
                #endif
            }
        } catch {
            session.commitConfiguration()
            return fail("Couldn't open the device: \(error.localizedDescription)")
        }
        session.commitConfiguration()
        applyAudio()
        sink.reset()
        await Task.detached { [session] in session.startRunning() }.value // startRunning blocks; keep off main

        activeFormat = currentFormat(device)
        let cs = CoreSession(sourceId: "uvc:\(UUID().uuidString)")
        coreSession = cs
        epoch = cs.epoch()
        for p in pipelines { p.attach(frames: sink.tap(), session: cs) }
        state = .running
        fpsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let (n, dropped) = self.sink.takeCounts()
                self.measuredFps = Double(n)
                self.droppedFrames += dropped
            }
        }
    }

    func stop() {
        fpsTimer?.invalidate(); fpsTimer = nil
        pipelines.forEach { $0.detach() }
        if session.isRunning { session.stopRunning() }
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        session.commitConfiguration()
        audioInput = nil
        coreSession = nil
        measuredFps = 0; droppedFrames = 0
        if state == .running || state == .starting { state = .idle }
    }

    private func currentFormat(_ d: AVCaptureDevice) -> CaptureFormatOption {
        let dims = CMVideoFormatDescriptionGetDimensions(d.activeFormat.formatDescription)
        let fps = d.activeVideoMinFrameDuration.seconds > 0 ? 1 / d.activeVideoMinFrameDuration.seconds : 0
        return CaptureFormatOption(width: Int(dims.width), height: Int(dims.height), maxFps: fps,
                                   pixelFormat: Self.fourcc(CMFormatDescriptionGetMediaSubType(d.activeFormat.formatDescription)),
                                   index: d.formats.firstIndex(of: d.activeFormat) ?? 0)
    }

    private func applyAudio() {
        #if os(macOS)
        audioPreview.volume = audioEnabled ? volume : 0
        #endif
    }

    // MARK: Hot-plug (README §5.5)

    private var lastDeviceId: String?

    private func deviceDisconnected(_ d: AVCaptureDevice?) {
        refreshDevices()
        guard let d, d.uniqueID == selectedDevice?.uniqueID, state == .running || state == .starting else { return }
        lastDeviceId = d.uniqueID
        if let cs = coreSession { epoch = cs.bump(reason: .reconnect) }
        pipelines.forEach { $0.invalidate() } // never leave a stale Thai line on a frozen frame
        stop()
        state = .disconnected("\(d.localizedName) was disconnected. Reconnect it to continue.")
    }

    private func deviceConnected(_ d: AVCaptureDevice?) {
        refreshDevices()
        guard let d, case .disconnected = state, d.uniqueID == lastDeviceId else { return }
        Task { await start(deviceId: d.uniqueID, format: nil, audioDeviceId: audioInput?.device.uniqueID) }
    }

    private func fail(_ msg: String) { state = .failed(msg) }

    static func requestAccess(_ type: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: type)
        default: return false
        }
    }
}

/// Receives capture frames on the video queue; keeps only the latest for OCR.
final class CaptureFrameSink: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, FrameSource, @unchecked Sendable {
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private var taken = true
    private var seq = 0
    private var frames = 0, dropped = 0

    func reset() { lock.lock(); latest = nil; taken = true; frames = 0; dropped = 0; lock.unlock() }

    /// Latest frame and its sequence number (for per-zone taps).
    func latestFrame() -> (CVPixelBuffer, Int)? {
        lock.lock(); defer { lock.unlock() }
        return latest.map { ($0, seq) }
    }

    /// A FrameSource for one zone: each zone sees every newest frame once, independently.
    func tap() -> FrameSource { FrameTap(sink: self) }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock(); latest = pb; taken = false; seq += 1; frames += 1; lock.unlock()
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lock.lock(); dropped += 1; lock.unlock()
    }

    func nextFrame() -> CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        guard !taken else { return nil }
        taken = true
        return latest
    }

    func takeCounts() -> (Int, Int) {
        lock.lock(); defer { frames = 0; dropped = 0; lock.unlock() }
        return (frames, dropped)
    }
}

final class FrameTap: FrameSource {
    private let sink: CaptureFrameSink
    private var lastSeq = 0
    init(sink: CaptureFrameSink) { self.sink = sink }
    func nextFrame() -> CVPixelBuffer? {
        guard let (pb, n) = sink.latestFrame(), n != lastSeq else { return nil }
        lastSeq = n
        return pb
    }
}
