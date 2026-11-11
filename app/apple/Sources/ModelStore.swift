import Foundation
import SwiftUI

/// Minimal model manager (FR-017 subset): user imports a local GGUF via the file picker
/// (README §3.3 "import compatible installed model"). No network; nothing is downloaded here.
@MainActor
final class ModelStore: ObservableObject {
    enum State: Equatable { case none, loading(String), ready(String), failed(String) }
    @Published private(set) var state: State = .none
    /// What the pipelines use: one model, or a LanguageRouter over two (ADR-0011).
    private(set) var translator: SubtitleTranslator?
    /// Every model currently in memory (freed together).
    private var loaded: [LlamaTranslator] = []
    /// macOS: English → Typhoon Translate when it is in ~/Models, everything else → the general model.
    static var routeByLanguage: Bool { UserDefaults.standard.object(forKey: "routeByLanguage") as? Bool ?? true }
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
        loaded.forEach { $0.shutdown() }
        loaded = []
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
        return ggufs.filter { !isTyphoonTranslate($0) }.min { (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 < (try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 }
        #else
        return nil
        #endif
    }

    nonisolated static func isTyphoonTranslate(_ url: URL) -> Bool {
        url.lastPathComponent.lowercased().contains("typhoon-translate")
    }

    static func findTyphoonTranslate() -> URL? {
        #if os(macOS)
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Models")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.first { $0.pathExtension.lowercased() == "gguf" && isTyphoonTranslate($0) }
        #else
        return nil // one model at a time on iPad (memory)
        #endif
    }

    func load(url: URL, remember: Bool = true) async {
        let name = url.deletingPathExtension().lastPathComponent
        unload() // free the previous model first: never hold two in memory
        state = .loading(name)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let first = try await LlamaTranslator.load(url: url)
            if terminating { first.shutdown(); return } // app quit while loading
            loaded = [first]
            translator = first
            state = .ready(name)
            await addLanguageRoute(picked: url, first: first)
            if remember, let data = try? url.bookmarkData(options: Self.bookmarkCreate) {
                UserDefaults.standard.set(data, forKey: bookmarkKey)
            }
        } catch {
            translator = nil
            state = .failed(error.localizedDescription)
        }
    }

    /// Pair the picked model with its counterpart: Typhoon Translate for English, a general model
    /// (Qwen) for Japanese and everything else. Failure keeps the single model.
    private func addLanguageRoute(picked: URL, first: LlamaTranslator) async {
        guard Self.routeByLanguage else { return }
        let pickedIsTT = Self.isTyphoonTranslate(picked)
        guard let otherURL = pickedIsTT ? Self.findLocalModel() : Self.findTyphoonTranslate(),
              otherURL.standardizedFileURL != picked.standardizedFileURL,
              let other = try? await LlamaTranslator.load(url: otherURL) else { return }
        if terminating { other.shutdown(); return }
        loaded.append(other)
        let (en, rest) = pickedIsTT ? (first, other) : (other, first)
        translator = LanguageRouter(english: en, other: rest)
        state = .ready("EN \(Self.short(en.modelId)) · JA \(Self.short(rest.modelId))")
    }

    static func short(_ id: String) -> String {
        let l = id.lowercased()
        if l.contains("typhoon-translate") { return "Typhoon Translate" }
        if l.contains("typhoon") { return "Typhoon" }
        if l.contains("qwen") { return "Qwen" }
        return id
    }

    #if os(macOS)
    static let bookmarkCreate: URL.BookmarkCreationOptions = [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
    static let bookmarkResolve: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #else
    static let bookmarkCreate: URL.BookmarkCreationOptions = []
    static let bookmarkResolve: URL.BookmarkResolutionOptions = []
    #endif
}

/// Routes English lines to one model and all others to another (ADR-0011). Cache identity
/// combines both models, so changing either never reuses old translations.
final class LanguageRouter: SubtitleTranslator, @unchecked Sendable {
    let english: SubtitleTranslator
    let other: SubtitleTranslator
    init(english: SubtitleTranslator, other: SubtitleTranslator) { self.english = english; self.other = other }

    var modelId: String { "en:\(english.modelId)+ja:\(other.modelId)" }
    var modelRevision: String { "\(english.modelRevision)+\(other.modelRevision)" }
    var quantizationId: String { "\(english.quantizationId)+\(other.quantizationId)" }
    var promptVersion: String { "en:\(english.promptVersion)+ja:\(other.promptVersion)" }

    func translate(_ request: TranslationRequest) async throws -> TranslationOutcome {
        try await (request.language == .english ? english : other).translate(request)
    }
}
