import SwiftUI

/// Live Capture screen (E07, FR-003, AC-016): choose a UVC device + format, preview with Thai overlay.
struct LiveCaptureScreen: View {
    @StateObject private var engine = LiveCaptureEngine()
    @EnvironmentObject private var models: ModelStore
    @State private var deviceId: String?
    @State private var formatId: String? // nil = Auto (§5.2 ladder)
    @State private var audioId: String?  // nil = no audio
    @State private var showDebug = false
    @State private var showModelPicker = false
    @State private var editingZone = false
    private static let zoneKey = "liveSubtitleZone"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch engine.state {
            case .running:
                PlayerSurface(layer: engine.previewLayer)
                    .overlay {
                        SubtitleOverlayView(pipeline: engine.pipeline,
                                            videoSize: CGSize(width: engine.activeFormat?.width ?? 1920,
                                                              height: engine.activeFormat?.height ?? 1080),
                                            showDebug: showDebug || editingZone)
                    }
                    .overlay {
                        if editingZone {
                            SubtitleZoneEditor(pipeline: engine.pipeline, videoSize: videoSize)
                        }
                    }
                    .overlay(alignment: .topTrailing) { if showDebug { captureStats } }
                    .accessibilityLabel("Live video")
            case .starting:
                ProgressView("Starting capture…").tint(.white).foregroundStyle(.white)
            default:
                setup
            }
        }
        .safeAreaInset(edge: .bottom) { if engine.state == .running { controls } }
        .navigationTitle("Live Capture")
        .toolbar { ToolbarItem { modelButton } }
        .fileImporter(isPresented: $showModelPicker, allowedContentTypes: [.data, .item]) { result in
            guard case .success(let url) = result else { return }
            if url.pathExtension.lowercased() == "gguf" { Task { await models.load(url: url) } }
            else { models.reject("\(url.lastPathComponent) is not a .gguf model file") }
        }
        .onReceive(models.$state) { _ in engine.pipeline.translator = models.translator }
        .onAppear {
            if let z = SubtitleZoneStore.load(Self.zoneKey) { engine.pipeline.roi = z }
            engine.refreshDevices()
            if deviceId == nil { deviceId = engine.devices.first?.id }
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "live"), let d = deviceId {
                showDebug = UserDefaults.standard.bool(forKey: "debugOverlay")
                Task { await engine.start(deviceId: d, format: nil, audioDeviceId: nil) }
            }
            #endif
        }
        .onDisappear { engine.stop() }
        .onChange(of: deviceId) { _, id in if let id { engine.select(deviceId: id); formatId = nil } }
    }

    // MARK: Setup

    private var setup: some View {
        Form {
            if let message = stateMessage {
                Section { Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
            Section("Capture device") {
                if engine.devices.isEmpty {
                    Text("No UVC capture device found. Connect a capture card (or USB camera), then Refresh.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Device", selection: $deviceId) {
                        ForEach(engine.devices) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Format", selection: $formatId) {
                        Text("Auto (prefer 1080p60)").tag(String?.none)
                        ForEach(engine.formats) { Text($0.label).tag(Optional($0.id)) }
                    }
                }
                Button("Refresh devices", systemImage: "arrow.clockwise") { engine.refreshDevices() }
            }
            #if os(macOS)
            Section {
                Picker("Audio", selection: $audioId) {
                    Text("None").tag(String?.none)
                    ForEach(engine.audioDevices) { Text($0.name).tag(Optional($0.id)) }
                }
            } header: { Text("Audio") } footer: {
                Text("Pick the capture card's audio. A webcam/microphone played to your speakers will echo.")
            }
            #endif
            Section {
                Button {
                    guard let d = deviceId else { return }
                    let f = engine.formats.first { $0.id == formatId }
                    Task { await engine.start(deviceId: d, format: f, audioDeviceId: audioId) }
                } label: { Label("Start capture", systemImage: "play.fill") }
                .disabled(deviceId == nil)
                .keyboardShortcut(.defaultAction)
            } footer: {
                Text("Only unprotected video is shown. Support is per tested device (see Device compatibility).")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 640)
        .onAppear { if let d = deviceId { engine.select(deviceId: d) } }
    }

    /// NFR-009: distinct messages for permission vs device vs stream.
    private var stateMessage: String? {
        switch engine.state {
        case .permissionDenied:
            #if os(macOS)
            return "Camera access is off. System Settings → Privacy & Security → Camera → allow AIVision, then try again."
            #else
            return "Camera access is off. Settings → AIVision → Camera, then try again."
            #endif
        case .disconnected(let m), .failed(let m): return m
        default: return nil
        }
    }

    // MARK: Running

    private var controls: some View {
        HStack(spacing: 16) {
            Button { engine.stop() } label: { Label("Stop", systemImage: "stop.fill") }
            Text(engine.activeFormat?.label ?? "").font(.caption.monospaced()).foregroundStyle(.secondary)
            #if os(macOS)
            if audioId != nil {
                Toggle("Audio", isOn: $engine.audioEnabled)
                Slider(value: $engine.volume, in: 0...1).frame(maxWidth: 120).accessibilityLabel("Volume")
            }
            #endif
            Spacer()
            PipelineControls(pipeline: engine.pipeline)
            Toggle(isOn: $editingZone) { Label("Subtitle zone", systemImage: "rectangle.dashed") }
                .toggleStyle(.button)
                .onChange(of: editingZone) { _, on in
                    if !on { SubtitleZoneStore.save(engine.pipeline.roi, Self.zoneKey) }
                }
            if editingZone {
                Button("Reset zone") { engine.pipeline.roi = SubtitleOCR.defaultRoi }
            }
            Toggle("Debug", isOn: $showDebug)
            Text("epoch \(engine.epoch)").font(.caption.monospaced()).foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .padding()
        .background(.bar)
    }

    private var videoSize: CGSize {
        CGSize(width: engine.activeFormat?.width ?? 1920, height: engine.activeFormat?.height ?? 1080)
    }

    private var captureStats: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("capture \(Int(engine.measuredFps)) fps · dropped \(engine.droppedFrames)")
            Text(engine.activeFormat?.label ?? "")
        }
        .font(.caption.monospaced()).foregroundStyle(.white)
        .padding(6).background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6)).padding(10)
    }

    @ViewBuilder private var modelButton: some View {
        switch models.state {
        case .none: Button("Choose model…", systemImage: "cpu") { showModelPicker = true }
        case .loading(let n): Label("Loading \(n)…", systemImage: "hourglass")
        case .ready(let n): Button(n, systemImage: "cpu.fill") { showModelPicker = true }
        case .failed(let e): Button("Model error", systemImage: "exclamationmark.triangle") { showModelPicker = true }.help(e)
        }
    }
}
