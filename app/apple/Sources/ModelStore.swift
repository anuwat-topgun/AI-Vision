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
    private var terminateObserver: NSObjectProtocol?

    init() {
        #if os(macOS)
        let name = NSApplication.willTerminateNotification
        #else
        let name = UIApplication.willTerminateNotification
        #endif
        terminateObserver = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.terminating = true; self?.unload() }
        }
    }

    /// Release the model (app quit, or before loading another one).
    private var terminating = false

    func unload() {
        translator?.shutdown()
        translator = nil
        if case .ready = state { state = .none }
    }

    /// Reload the last chosen model; otherwise pick up a local GGUF from ~/Models (macOS).
    /// Local disk only — never downloads.
    func restore() async {
        // The XCTest host is this app; tests load their own model and end via exit().
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        guard translator == nil, !isLoading else { return }
        if let data = UserDefaults.standard.data(forKey: bookmarkKey) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: Self.bookmarkResolve, bookmarkDataIsStale: &stale),
               FileManager.default.fileExists(atPath: url.path) {
                await load(url: url, remember: stale)
                return
            }
        }
        if let found = Self.findLocalModel() { await load(url: found) }
    }

    func reject(_ message: String) { if translator == nil { state = .failed(message) } }

    var isLoading: Bool { if case .loading = state { true } else { false } }

    /// Largest-first is not wanted; prefer the tested model, else the smallest .gguf (fits memory).
    static func findLocalModel() -> URL? {
        #if os(macOS)
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Models")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let ggufs = files.filter { $0.pathExtension.lowercased() == "gguf" }
        if let tested = ggufs.first(where: { $0.lastPathComponent == "Qwen3-4B-Instruct-2507-Q4_K_M.gguf" }) { return tested }
        return ggufs.min { (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 < (try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 }
        #else
        return nil
        #endif
    }

    func load(url: URL, remember: Bool = true) async {
        let name = url.deletingPathExtension().lastPathComponent
        unload() // free the previous model first: never hold two in memory
        state = .loading(name)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let loaded = try await LlamaTranslator.load(url: url)
            if terminating { loaded.shutdown(); return } // app quit while loading
            translator = loaded
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
