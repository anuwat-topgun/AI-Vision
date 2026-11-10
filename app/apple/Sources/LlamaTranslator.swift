import Foundation
import llama

/// Offline EN/JA→TH translator on llama.cpp (E04 candidate adapter; D-001 still open).
/// All inference runs on a private serial queue; the main/render threads never wait on it.
final class LlamaTranslator: SubtitleTranslator, @unchecked Sendable {
    enum LlamaError: LocalizedError {
        case loadFailed(String), contextFailed, tokenizeFailed, decodeFailed(Int32), promptTooLong, unknownPrompt(String)
        var errorDescription: String? {
            switch self {
            case .loadFailed(let p): "Couldn't load model at \(p)"
            case .contextFailed: "Couldn't create inference context (not enough memory?)"
            case .tokenizeFailed: "Tokenizer failed"
            case .decodeFailed(let c): "Inference failed (code \(c))"
            case .promptTooLong: "Subtitle + context too long for the model context"
            case .unknownPrompt(let v): "Unknown prompt version \(v)"
            }
        }
    }

    let modelId: String
    /// Cache identity parts (§8): file size + mtime as revision, quantization from file name.
    let modelRevision: String
    let quantizationId: String
    /// Active prompt (rollback: set UserDefaults `promptVersion` = p1). Never mixes caches.
    var promptVersion: String = UserDefaults.standard.string(forKey: "promptVersion") ?? defaultPromptVersion()
    private let queue = DispatchQueue(label: "aivision.llama", qos: .userInitiated)
    private let model: OpaquePointer
    private let ctx: OpaquePointer
    private let vocab: OpaquePointer
    private let template: String?
    private let maxOutputTokens: Int32 = 160
    static let batchSize = 512
    private let nBatch = LlamaTranslator.batchSize
    private let generation = ManagedAtomicCounter()
    /// Tokens currently held in the KV cache (only touched on `queue`).
    private var kvTokens: [llama_token] = []

    /// Loads synchronously; call off the main thread (see `load(url:)`).
    init(modelURL: URL) throws {
        // ggml aborts at process exit if Metal residency sets are still registered (quit during
        // model load, or exit() without willTerminate). Residency sets are only a paging hint.
        setenv("GGML_METAL_NO_RESIDENCY", "1", 0)
        llama_backend_init()
        var mp = llama_model_default_params()
        mp.n_gpu_layers = 99 // Metal offload where available
        guard let m = llama_model_load_from_file(modelURL.path, mp) else {
            throw LlamaError.loadFailed(modelURL.lastPathComponent)
        }
        var cp = llama_context_default_params()
        cp.n_ctx = 2048
        cp.n_batch = UInt32(LlamaTranslator.batchSize)
        cp.n_threads = Int32(max(2, ProcessInfo.processInfo.activeProcessorCount - 2))
        cp.n_threads_batch = cp.n_threads
        guard let c = llama_init_from_model(m, cp) else { llama_model_free(m); throw LlamaError.contextFailed }
        model = m; ctx = c
        vocab = llama_model_get_vocab(m)
        template = llama_model_chat_template(m, nil).map { String(cString: $0) }
        let name = modelURL.deletingPathExtension().lastPathComponent
        modelId = name
        let attrs = try? FileManager.default.attributesOfItem(atPath: modelURL.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let mtime = Int64((attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
        modelRevision = "\(size)-\(mtime)"
        quantizationId = name.range(of: #"(?i)(IQ|Q)\d[A-Z0-9_]*$"#, options: .regularExpression).map { String(name[$0]) } ?? "unknown"
    }

    static func load(url: URL) async throws -> LlamaTranslator {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(with: Result { try LlamaTranslator(modelURL: url) })
            }
        }
    }

    private var freed = false

    /// Free Metal/llama resources now. Must run before process exit: if the model is still
    /// alive when ggml's global Metal device is destroyed, ggml aborts ("quit unexpectedly").
    func shutdown() {
        _ = generation.increment() // stop any running generation at the next token
        queue.sync {
            guard !freed else { return }
            freed = true
            llama_free(ctx)
            llama_model_free(model)
            kvTokens = []
        }
    }

    deinit { shutdown() }

    func translate(_ request: TranslationRequest) async throws -> TranslationOutcome {
        try await translate(request, promptVersion: promptVersion)
    }

    /// `promptVersion` override is for A/B tests; production uses the configured version.
    func translate(_ request: TranslationRequest, promptVersion: String) async throws -> TranslationOutcome {
        guard case .ok(let clean, _) = sanitizeSubtitle(input: request.sourceText) else {
            return .unreadable // §5 rule 5: don't ask the model about non-language input
        }
        guard let system = promptText(version: promptVersion) else { throw LlamaError.unknownPrompt(promptVersion) }
        let gen = generation.increment() // newer request cancels older ones between tokens
        let msgs = Self.buildMessages(system: system, current: clean, language: request.language, history: request.history)
        let (raw, hitCap) = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                queue.async { [self] in cont.resume(with: Result { try self.run(messages: msgs, gen: gen) }) }
            }
        } onCancel: { [generation] in
            _ = generation.increment()
        }
        switch parseTranslation(raw: raw, source: clean, hitTokenCap: hitCap) {
        case .translated(let text): return .translated(text)
        case .unreadable: return .unreadable
        case .invalid(let reason): return .invalid(reason)
        }
    }


    /// Messages per spec §4.1: system (canonical, from core) + ≤3 history pairs + current user turn.
    /// Roles and wrappers are created here, never from OCR text (§4.3).
    static func buildMessages(system: String, current: String, language: FfiSourceLanguage,
                              history: [FfiHistoryPair]) -> [(String, String)] {
        var msgs: [(String, String)] = [("system", system)]
        for h in history.suffix(3) {
            msgs.append(("user", buildUserMessage(language: h.language, sanitizedText: h.source)))
            msgs.append(("assistant", h.thai))
        }
        msgs.append(("user", buildUserMessage(language: language, sanitizedText: current)))
        return msgs
    }

    // MARK: - Inference (runs on `queue`)

    private func applyTemplate(_ msgs: [(String, String)]) -> String {
        let cStrings = msgs.map { (strdup($0.0)!, strdup($0.1)!) }
        defer { cStrings.forEach { free($0.0); free($0.1) } }
        var chat = cStrings.map { llama_chat_message(role: $0.0, content: $0.1) }
        var buf = [CChar](repeating: 0, count: 8192)
        var n = llama_chat_apply_template(template, &chat, chat.count, true, &buf, Int32(buf.count))
        if n > buf.count {
            buf = [CChar](repeating: 0, count: Int(n) + 1)
            n = llama_chat_apply_template(template, &chat, chat.count, true, &buf, Int32(buf.count))
        }
        guard n > 0 else { // fallback: ChatML (Qwen family)
            return msgs.map { "<|im_start|>\($0.0)\n\($0.1)<|im_end|>\n" }.joined() + "<|im_start|>assistant\n"
        }
        return String(decoding: buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private func run(messages: [(String, String)], gen: UInt64) throws -> (String, Bool) {
        if freed { throw CancellationError() }
        let prompt = applyTemplate(messages)
        let utf8 = Array(prompt.utf8CString)
        var tokens = [llama_token](repeating: 0, count: utf8.count + 16)
        let nTok = llama_tokenize(vocab, prompt, Int32(utf8.count - 1), &tokens, Int32(tokens.count), true, true)
        guard nTok > 0 else { throw LlamaError.tokenizeFailed }
        tokens.removeLast(tokens.count - Int(nTok))

        // Must fit the context with room for output; llama.cpp aborts (not errors) on overflow.
        guard Int(nTok) + Int(maxOutputTokens) < Int(llama_n_ctx(ctx)) else { throw LlamaError.promptTooLong }

        // Prefix reuse: keep KV for the tokens shared with the previous request (the long system
        // prompt + unchanged history) and only decode the new tail. Same output as a full
        // recompute under greedy decoding; removes most of p2's extra prefill cost.
        let mem = llama_get_memory(ctx)
        var common = 0
        while common < min(kvTokens.count, tokens.count), kvTokens[common] == tokens[common] { common += 1 }
        if common == tokens.count { common -= 1 } // must decode ≥1 token to get fresh logits
        if common == 0 {
            llama_memory_clear(mem, true)
        } else {
            _ = llama_memory_seq_rm(mem, 0, llama_pos(common), -1)
        }
        kvTokens = Array(tokens[..<common])
        var offset = common
        while offset < tokens.count {
            let n = min(nBatch, tokens.count - offset)
            let rc = tokens.withUnsafeMutableBufferPointer { llama_decode(ctx, llama_batch_get_one($0.baseAddress! + offset, Int32(n))) }
            guard rc == 0 else { llama_memory_clear(mem, true); kvTokens = []; throw LlamaError.decodeFailed(rc) }
            kvTokens += tokens[offset..<(offset + n)]
            offset += n
        }

        let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        defer { llama_sampler_free(sampler) }
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy()) // deterministic for golden tests

        var bytes: [UInt8] = []
        var piece = [CChar](repeating: 0, count: 256)
        var hitCap = true // stays true only if we exhaust max tokens without EOG/newline (§6.1)
        for _ in 0..<maxOutputTokens {
            if generation.value != gen { throw CancellationError() }
            var tok = llama_sampler_sample(sampler, ctx, -1)
            if llama_vocab_is_eog(vocab, tok) { hitCap = false; break }
            let n = llama_token_to_piece(vocab, tok, &piece, Int32(piece.count), 0, false)
            if n > 0 { bytes += piece.prefix(Int(n)).map { UInt8(bitPattern: $0) } }
            if bytes.contains(0x0A), !String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                hitCap = false; break // one line is enough
            }
            let rc = llama_decode(ctx, llama_batch_get_one(&tok, 1))
            guard rc == 0 else { llama_memory_clear(llama_get_memory(ctx), true); kvTokens = []; throw LlamaError.decodeFailed(rc) }
            kvTokens.append(tok)
        }
        return (String(decoding: bytes, as: UTF8.self), hitCap)
    }
}

/// Tiny lock-protected counter (avoids pulling in swift-atomics).
final class ManagedAtomicCounter: @unchecked Sendable {
    private var v: UInt64 = 0
    private let lock = NSLock()
    var value: UInt64 { lock.lock(); defer { lock.unlock() }; return v }
    func increment() -> UInt64 { lock.lock(); defer { lock.unlock() }; v += 1; return v }
}
