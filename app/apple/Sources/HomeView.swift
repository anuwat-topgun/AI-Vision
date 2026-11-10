import SwiftUI

/// Home: File and Live Capture visibly separate (README §11.2).
/// File Input is permanent (ADR-0003, AC-004) — never hide it behind a debug flag.
struct HomeView: View {
    @State private var notice: String?
    private let coreVersion = coreApiVersion()

    var body: some View {
        NavigationStack {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { tiles }
                VStack(spacing: 16) { tiles }
            }
            .padding()
            .navigationTitle("AI Vision — EN/JA → ไทย")
            .safeAreaInset(edge: .bottom) {
                Text("Offline mode · Cloud off · core API v\(coreVersion)")
                    .font(.footnote).foregroundStyle(.secondary).padding(8)
            }
            .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {}
        }
    }

    @ViewBuilder private var tiles: some View {
        ModeTile(systemImage: "film", title: "Video File / ไฟล์วิดีโอ",
                 subtitle: "MP4 / MOV / MKV (where supported)") {
            notice = "File adapter not implemented yet (E02)"
        }
        .accessibilityIdentifier("tile_file")
        ModeTile(systemImage: "cable.connector", title: "Live Capture / จับภาพสด",
                 subtitle: "UVC capture card — qualified devices only") {
            notice = "UVC adapter not implemented yet (E06/E07)"
        }
        .accessibilityIdentifier("tile_live")
    }
}

struct ModeTile: View {
    let systemImage: String, title: String, subtitle: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: systemImage).font(.system(size: 48))
                Text(title).font(.title2.weight(.semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 200)
            .padding()
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
