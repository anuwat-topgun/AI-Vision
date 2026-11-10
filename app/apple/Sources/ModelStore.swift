import Foundation
import SwiftUI

/// Minimal model manager (FR-017 subset): user imports a local GGUF via the file picker
/// (README §3.3 "import compatible installed model"). No network; nothing is downloaded here.
@MainActor
final class ModelStore: ObservableObject {
    enum State: Equatable { case none, loading(String), ready(String), failed(String) }
    @Published private(set) var state: State = .none
    private(set) var translator: LlamaTranslator?
    private let bookmarkKey = "llamaModelBookmark"

    /// Reload the last chosen model, if any.
    func restore() async {
        guard translator == nil, let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: Self.bookmarkResolve, bookmarkDataIsStale: &stale) else { return }
        await load(url: url, remember: false)
    }

    func load(url: URL, remember: Bool = true) async {
        let name = url.deletingPathExtension().lastPathComponent
        state = .loading(name)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            translator = try await LlamaTranslator.load(url: url)
            state = .ready(name)
            if remember, let data = try? url.bookmarkData(options: Self.bookmarkCreate) {
                UserDefaults.standard.set(data, forKey: bookmarkKey)
            }
        } catch {
            translator = nil
            state = .failed(error.localizedDescription)
        }
    }

    #if os(macOS)
    static let bookmarkCreate: URL.BookmarkCreationOptions = [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
    static let bookmarkResolve: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #else
    static let bookmarkCreate: URL.BookmarkCreationOptions = []
    static let bookmarkResolve: URL.BookmarkResolutionOptions = []
    #endif
}
