import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// AVPlayerLayer host: native video surface, no frame copies (README §4.1).
#if os(macOS)
struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        v.layer = layer
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
#else
final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerLayerView {
        let v = PlayerLayerView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        v.backgroundColor = .black
        return v
    }
    func updateUIView(_ uiView: PlayerLayerView, context: Context) {}
}
#endif

/// Containers we offer in the picker; actual codec support is checked on open (FR-001).
let videoFileTypes: [UTType] = [.mpeg4Movie, .quickTimeMovie, .movie] + [UTType(filenameExtension: "mkv")].compactMap { $0 }

struct FilePlayerScreen: View {
    @StateObject private var model = PlayerModel()
    @EnvironmentObject private var models: ModelStore
    @State private var showModelPicker = false
    @State private var showDebug = false
    @State private var showPicker = DevLaunch.file == nil
    @State private var fullscreen = false
    @State private var scrub: Double?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.state {
            case .ready:
                PlayerSurface(player: model.player)
                    .overlay { SubtitleOverlayView(pipeline: model.pipeline, videoSize: model.videoSize, showDebug: showDebug) }
                    .ignoresSafeArea(edges: fullscreen ? .all : [])
                    .accessibilityLabel("Video")
                    .onTapGesture { withAnimation { fullscreen.toggle() } }
            case .loading:
                ProgressView("Opening…").tint(.white).foregroundStyle(.white)
            case .failed(let msg):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text(msg).multilineTextAlignment(.center)
                    Button("Choose another file") { showPicker = true }
                }.foregroundStyle(.white).padding()
            case .idle:
                Button("Choose a video file") { showPicker = true }.buttonStyle(.borderedProminent)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.state == .ready && !fullscreen { controls }
        }
        .navigationTitle("Video File")
        #if os(iOS)
        .toolbar(fullscreen ? .hidden : .visible, for: .navigationBar)
        .statusBarHidden(fullscreen)
        #endif
        .toolbar {
            ToolbarItem { Button("Open", systemImage: "folder") { showPicker = true } }
            ToolbarItem { modelButton }
        }
        .fileImporter(isPresented: $showModelPicker,
                      allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data]) { result in
            if case .success(let url) = result { Task { await models.load(url: url) } }
        }
        .task {
            #if DEBUG
            if let m = DevLaunch.model { await models.load(url: m, remember: false) }
            if let f = DevLaunch.file { await model.open(url: f); showDebug = DevLaunch.debug; model.togglePlay() }
            #endif
            await models.restore()
        }
        .onReceive(models.$state) { _ in model.pipeline.translator = models.translator }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: videoFileTypes) { result in
            if case .success(let url) = result { Task { await model.open(url: url) } }
        }
        .onDisappear { model.close() }
    }

    @ViewBuilder private var modelButton: some View {
        switch models.state {
        case .none: Button("Choose model…", systemImage: "cpu") { showModelPicker = true }
        case .loading(let n): Label("Loading \(n)…", systemImage: "hourglass")
        case .ready(let n): Button(n, systemImage: "cpu.fill") { showModelPicker = true }.help("Offline model ready")
        case .failed(let e): Button("Model error", systemImage: "exclamationmark.triangle") { showModelPicker = true }.help(e)
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Text(PlayerModel.format(scrub ?? model.currentTime)).monospacedDigit()
                Slider(value: Binding(get: { scrub ?? model.currentTime }, set: { scrub = $0 }),
                       in: 0...max(model.duration, 0.1)) { editing in
                    if !editing, let s = scrub { Task { await model.seek(to: s); scrub = nil } }
                }
                .accessibilityLabel("Playback position")
                Text(PlayerModel.format(model.duration)).monospacedDigit()
            }
            HStack(spacing: 20) {
                Button { Task { await model.skip(-10) } } label: { Image(systemName: "gobackward.10") }
                    .accessibilityLabel("Back 10 seconds").keyboardShortcut(.leftArrow, modifiers: [])
                Button { model.togglePlay() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.title)
                }
                .accessibilityLabel(model.isPlaying ? "Pause" : "Play").keyboardShortcut(.space, modifiers: [])
                Button { Task { await model.skip(10) } } label: { Image(systemName: "goforward.10") }
                    .accessibilityLabel("Forward 10 seconds").keyboardShortcut(.rightArrow, modifiers: [])
                Picker("Speed", selection: $model.rate) {
                    ForEach(PlayerModel.speeds, id: \.self) { Text("\($0, specifier: "%g")×").tag($0) }
                }.frame(maxWidth: 110)
                Button { model.isMuted.toggle() } label: {
                    Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }.accessibilityLabel(model.isMuted ? "Unmute" : "Mute")
                Slider(value: $model.volume, in: 0...1).frame(maxWidth: 140).accessibilityLabel("Volume")
                Button { withAnimation { fullscreen = true } } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }.accessibilityLabel("Fullscreen")
                Spacer()
                PipelineControls(pipeline: model.pipeline)
                Toggle("Debug", isOn: $showDebug)
                Text("epoch \(model.epoch)").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .background(.bar)
    }
}

/// Separate view so SwiftUI observes the nested pipeline object directly.
struct PipelineControls: View {
    @ObservedObject var pipeline: SubtitlePipeline
    var body: some View {
        Picker("Source", selection: $pipeline.hint) {
            ForEach(LanguageHint.allCases) { Text($0.label).tag($0) }
        }.frame(maxWidth: 150).accessibilityLabel("Subtitle language")
        Toggle("ไทย", isOn: $pipeline.enabled).accessibilityLabel("Thai translation")
    }
}

/// DEBUG-only launch arguments for local E2E runs, e.g.
/// `AIVision -file /path/video.mp4 -model ~/Models/x.gguf -debugOverlay YES`. Not in Release builds.
enum DevLaunch {
    #if DEBUG
    static var file: URL? { UserDefaults.standard.string(forKey: "file").map(URL.init(fileURLWithPath:)) }
    static var model: URL? { UserDefaults.standard.string(forKey: "model").map(URL.init(fileURLWithPath:)) }
    static var debug: Bool { UserDefaults.standard.bool(forKey: "debugOverlay") }
    #else
    static let file: URL? = nil
    #endif
}
