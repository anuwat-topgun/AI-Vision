import SwiftUI

/// Game profiles (prompt p3, ADR-0010): bundled JSON in `profiles/` plus the player's own files in
/// Application Support/AIVision/Profiles. The selected profile is remembered.
@MainActor
final class GameProfileStore: ObservableObject {
    struct Entry: Identifiable {
        let id: String
        let title: String
        let profile: GameProfile
        let url: URL
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var errors: [String] = []
    @Published var selectedId: String? {
        didSet { UserDefaults.standard.set(selectedId, forKey: Self.selectedKey) }
    }
    var active: GameProfile? { entries.first { $0.id == selectedId }?.profile }

    static let selectedKey = "gameProfileId"

    static var userDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("AIVision/Profiles", isDirectory: true)
    }

    init() {
        selectedId = UserDefaults.standard.string(forKey: Self.selectedKey)
        reload()
    }

    /// User files override bundled ones with the same id.
    func reload() {
        try? FileManager.default.createDirectory(at: Self.userDirectory, withIntermediateDirectories: true)
        var byId: [String: Entry] = [:]
        var errs: [String] = []
        let bundled = Bundle.main.url(forResource: "profiles", withExtension: nil)
        for dir in [bundled, Self.userDirectory].compactMap({ $0 }) {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for url in files where url.pathExtension.lowercased() == "json" {
                do {
                    let p = try GameProfile.fromJson(json: String(contentsOf: url, encoding: .utf8))
                    byId[p.id()] = Entry(id: p.id(), title: p.title(), profile: p, url: url)
                } catch {
                    errs.append("\(url.lastPathComponent): \(error)")
                }
            }
        }
        entries = byId.values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        errors = errs
    }
}

/// "Game" menu: pick the profile used for translation.
struct GameProfileMenu: View {
    @EnvironmentObject private var store: GameProfileStore
    var body: some View {
        Menu {
            Picker("Game profile", selection: $store.selectedId) {
                Text("None (generic)").tag(String?.none)
                ForEach(store.entries) { Text($0.title).tag(Optional($0.id)) }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Reload profiles", systemImage: "arrow.clockwise") { store.reload() }
            #if os(macOS)
            Button("Open profiles folder", systemImage: "folder") {
                NSWorkspace.shared.open(GameProfileStore.userDirectory)
            }
            #endif
            ForEach(store.errors, id: \.self) { Text("⚠︎ \($0)") }
        } label: {
            Label(store.entries.first { $0.id == store.selectedId }?.title ?? "No game", systemImage: "gamecontroller")
        }
        .fixedSize()
        .accessibilityLabel("Game profile")
    }
}
