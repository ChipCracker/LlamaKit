//
//  LlamaEngine.swift
//  Swift wrapper around the llama.cpp C API (module `llama`).
//
//  Inference is blocking, so the engine is an `actor` that serialises all calls
//  and keeps them off the main thread. Generation is streamed token-by-token via
//  a callback (or an `AsyncStream`). The prompt + tool-call *format* is pluggable
//  (`ChatFormat`, default Qwen3.5); the context-window mechanics live here.
//
//  Verified against llama.cpp @ tag b9488 (ggml 0.13.x). On API updates, re-check
//  the symbols against the xcframework's Headers/llama.h.
//
import Foundation
import llama

public actor LlamaEngine {
    /// Sensible GPU default per environment: Metal (offload all layers) on real
    /// devices, CPU in the iOS simulator (whose software Metal driver can't
    /// reliably allocate ggml buffers).
    public static var preferredNGpuLayers: Int32 {
        #if targetEnvironment(simulator)
        return 0
        #else
        return 999
        #endif
    }

    private let model: OpaquePointer
    private let ctx: OpaquePointer
    private let vocab: OpaquePointer
    private let contextLength: Int
    private let chatFormat: AnyChatFormat

    /// Initialise the llama backend once per process.
    private static let backendInit: Void = {
        llama_backend_init()
    }()

    public init(modelPath: String,
                nGpuLayers: Int32,
                contextLength: Int = 4096,
                chatFormat: AnyChatFormat = .qwen35) throws {
        _ = Self.backendInit

        var mparams = llama_model_default_params()
        mparams.n_gpu_layers = nGpuLayers
        guard let model = llama_model_load_from_file(modelPath, mparams) else {
            throw LlamaError.modelLoadFailed(modelPath)
        }

        var cparams = llama_context_default_params()
        cparams.n_ctx = UInt32(contextLength)
        cparams.n_batch = 512
        let cores = Int32(ProcessInfo.processInfo.activeProcessorCount)
        cparams.n_threads = max(1, cores - 1)
        cparams.n_threads_batch = cparams.n_threads
        guard let ctx = llama_init_from_model(model, cparams) else {
            llama_model_free(model)
            throw LlamaError.contextInitFailed
        }

        self.model = model
        self.ctx = ctx
        self.vocab = llama_model_get_vocab(model)
        self.contextLength = Int(llama_n_ctx(ctx))
        self.chatFormat = chatFormat
    }

    deinit {
        llama_free(ctx)
        llama_model_free(model)
    }

    /// Creates the engine on a background thread (model loading blocks).
    public static func make(modelPath: String,
                            nGpuLayers: Int32,
                            contextLength: Int = 4096,
                            chatFormat: AnyChatFormat = .qwen35) async throws -> LlamaEngine {
        try await Task.detached(priority: .userInitiated) {
            try LlamaEngine(modelPath: modelPath, nGpuLayers: nGpuLayers,
                            contextLength: contextLength, chatFormat: chatFormat)
        }.value
    }

    /// Convenience: load a downloaded `ModelSpec`, wiring its chat format so you
    /// can't accidentally use the wrong prompt template for the weights.
    public static func make(spec: ModelSpec,
                            downloadedAt url: URL,
                            nGpuLayers: Int32 = LlamaEngine.preferredNGpuLayers,
                            contextLength: Int = 4096) async throws -> LlamaEngine {
        try await make(modelPath: url.path, nGpuLayers: nGpuLayers,
                       contextLength: contextLength, chatFormat: spec.chatFormat)
    }

    // MARK: - Generation (callback API)

    /// Generates a reply to `history`, streaming each decoded piece via `onToken`
    /// and reporting tool calls via `onTool`; returns the run statistics.
    ///
    /// `shouldContinue` is checked before each step → allows external cancellation.
    /// The conversation is rebuilt from history each round and the KV cache is
    /// cleared beforehand (simple, robust, no position bookkeeping).
    @discardableResult
    public func generate(history: [ChatTurn],
                         tools: [LLMTool] = [],
                         options: GenerationOptions = .init(),
                         shouldContinue: @escaping @Sendable () -> Bool = { true },
                         onToken: @escaping @Sendable (String) -> Void,
                         onTool: @escaping @Sendable (ToolInvocation) -> Void = { _ in }) async -> GenerationStats {

        var stats = GenerationStats()
        var convo = history
        let toolsByName = Dictionary(tools.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let canUseTools = !tools.isEmpty && chatFormat.toolCallTerminator != nil
        let maxRounds = canUseTools ? max(1, options.maxToolRounds) : 1
        let thinking = options.thinking
        let maxTokens = options.maxTokens
        let terminator = chatFormat.toolCallTerminator
        let boundary = chatFormat.visibleBoundaryMarker

        let smpl = makeSampler(options.sampling)
        defer { llama_sampler_free(smpl) }
        let tGen0 = Date()

        roundLoop: for round in 0..<maxRounds {
            if !shouldContinue() { break }

            // Clear the KV cache → re-prefill the whole (growing) conversation.
            llama_memory_clear(llama_get_memory(ctx), true)
            let prompt = chatFormat.buildPrompt(history: convo, thinking: thinking,
                                                tools: canUseTools ? tools : [])
            var tokens = tokenize(prompt, addSpecial: false, parseSpecial: true)
            if round == 0 { stats.promptTokens = tokens.count }
            guard !tokens.isEmpty else { break }

            // Prefill in chunks ≤ n_batch (otherwise GGML_ASSERT(n_tokens_all <=
            // cparams.n_batch) fires). Successive llama_batch_get_one calls
            // continue the positions automatically.
            let tP0 = Date()
            let nBatch = max(1, Int(llama_n_batch(ctx)))
            let prefillOK = tokens.withUnsafeMutableBufferPointer { buf -> Bool in
                var offset = 0
                while offset < buf.count {
                    let chunk = min(nBatch, buf.count - offset)
                    let batch = llama_batch_get_one(buf.baseAddress!.advanced(by: offset), Int32(chunk))
                    if llama_decode(ctx, batch) != 0 { return false }
                    offset += chunk
                }
                return true
            }
            if round == 0 { stats.promptSeconds = Date().timeIntervalSince(tP0) }
            guard prefillOK else { break }

            // Any prompt prefill text (e.g. the open `<think>\n`) is part of the
            // prompt, not generated → feed it to the stream so UIs see it.
            if let prefill = chatFormat.thinkingPrefill(thinking: thinking) { onToken(prefill) }

            // --- Token-by-token generation for this round ---
            var roundText = ""        // generated text only (without the prefill)
            var streamedChars = 0     // chars already streamed as visible
            var nDecoded = tokens.count
            var cur = llama_sampler_sample(smpl, ctx, -1)
            var toolDetected = false
            // UTF-8-Bytes, die am Token-Ende eine unvollständige Mehrbyte-Sequenz
            // bilden (z. B. ein über mehrere Tokens verteiltes Emoji) → erst
            // dekodieren, wenn die Sequenz mit dem nächsten Token komplett ist.
            var pendingBytes: [UInt8] = []

            while stats.generatedTokens < maxTokens, shouldContinue() {
                if llama_vocab_is_eog(vocab, cur) { break }

                pendingBytes += pieceBytes(for: cur)
                let (decoded, rest) = Self.splitValidUTF8(pendingBytes)
                pendingBytes = rest
                roundText += decoded
                stats.generatedTokens += 1
                streamVisible(roundText, alreadyStreamed: &streamedChars,
                              boundary: boundary, onToken: onToken)

                if let terminator, roundText.contains(terminator) { toolDetected = true; break }
                if nDecoded + 1 >= contextLength { break roundLoop }

                var next = cur
                let ok = withUnsafeMutablePointer(to: &next) { p -> Bool in
                    llama_decode(ctx, llama_batch_get_one(p, 1)) == 0
                }
                if !ok { break roundLoop }
                nDecoded += 1
                cur = llama_sampler_sample(smpl, ctx, -1)
            }
            // Restbytes einer am Rundenende unvollständigen UTF-8-Sequenz flushen.
            if !pendingBytes.isEmpty {
                roundText += String(decoding: pendingBytes, as: UTF8.self)
                pendingBytes = []
                streamVisible(roundText, alreadyStreamed: &streamedChars,
                              boundary: boundary, onToken: onToken)
            }

            // No (parseable) tool call → finished answer.
            guard canUseTools, toolDetected, let call = chatFormat.parseToolCall(roundText) else { break }

            // Run the tool (or report an error for an unknown function).
            let result: String
            if let tool = toolsByName[call.name] {
                result = await tool.run(call.arguments)
            } else {
                result = "Error: unknown function \"\(call.name)\""
            }
            onTool(ToolInvocation(name: call.name, arguments: call.arguments, result: result))

            // Append the assistant tool-call turn + tool-response turn, then the
            // next round generates the final answer.
            convo.append(contentsOf: chatFormat.toolResultTurns(forAssistant: roundText,
                                                                result: result, thinking: thinking))
        }

        stats.generationSeconds = Date().timeIntervalSince(tGen0)
        return stats
    }

    // MARK: - Generation (AsyncStream API)

    /// `AsyncStream` variant over the same decode loop. Cancel by terminating the
    /// stream (e.g. breaking out of the `for await` loop / cancelling the task).
    public nonisolated func generate(history: [ChatTurn],
                                     tools: [LLMTool] = [],
                                     options: GenerationOptions = .init()) -> AsyncStream<GenerationEvent> {
        AsyncStream { continuation in
            let task = Task {
                let stats = await self.generate(
                    history: history, tools: tools, options: options,
                    shouldContinue: { !Task.isCancelled },
                    onToken: { continuation.yield(.token($0)) },
                    onTool: { continuation.yield(.tool($0)) })
                continuation.yield(.finished(stats))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Streams the not-yet-emitted text before the format's visible boundary
    /// marker (raw tool-call markup after it stays hidden).
    private func streamVisible(_ text: String, alreadyStreamed: inout Int,
                               boundary: String?, onToken: (String) -> Void) {
        let end: String.Index
        if let boundary, let r = text.range(of: boundary) { end = r.lowerBound } else { end = text.endIndex }
        let visible = Array(text[text.startIndex..<end])
        if visible.count > alreadyStreamed {
            onToken(String(visible[alreadyStreamed...]))
            alreadyStreamed = visible.count
        }
    }

    // MARK: - Sampler

    private func makeSampler(_ p: SamplingParams) -> UnsafeMutablePointer<llama_sampler> {
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        if p.temperature <= 0 {
            llama_sampler_chain_add(chain, llama_sampler_init_greedy())
        } else {
            llama_sampler_chain_add(chain, llama_sampler_init_top_k(p.topK))
            llama_sampler_chain_add(chain, llama_sampler_init_top_p(p.topP, 1))
            llama_sampler_chain_add(chain, llama_sampler_init_min_p(p.minP, 1))
            llama_sampler_chain_add(chain, llama_sampler_init_temp(p.temperature))
            llama_sampler_chain_add(chain, llama_sampler_init_dist(p.seed))
        }
        return chain
    }

    // MARK: - Tokenisation

    private func tokenize(_ text: String, addSpecial: Bool, parseSpecial: Bool) -> [llama_token] {
        let utf8 = Array(text.utf8)
        let nMax = utf8.count + 16
        var tokens = [llama_token](repeating: 0, count: nMax)
        let n = utf8.withUnsafeBufferPointer { bytes in
            bytes.baseAddress!.withMemoryRebound(to: CChar.self, capacity: bytes.count) { cstr in
                llama_tokenize(vocab, cstr, Int32(bytes.count),
                               &tokens, Int32(nMax), addSpecial, parseSpecial)
            }
        }
        guard n > 0 else { return [] }
        return Array(tokens.prefix(Int(n)))
    }

    /// Raw UTF-8 bytes of a single token's text piece. Decoding is deferred across
    /// tokens (see `splitValidUTF8`): byte-level BPE can split a multi-byte
    /// character (e.g. an emoji) over several tokens, so decoding each token in
    /// isolation would yield U+FFFD replacement characters.
    private func pieceBytes(for token: llama_token) -> [UInt8] {
        var size = 64
        while true {
            var buf = [CChar](repeating: 0, count: size)
            let n = llama_token_to_piece(vocab, token, &buf, Int32(size), 0, /*special=*/false)
            if n < 0 {
                size = Int(-n)
                continue
            }
            return buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }
        }
    }

    /// Splits a byte buffer at the last COMPLETE UTF-8 sequence boundary: returns
    /// the decodable prefix as a `String` plus the leftover trailing bytes of an
    /// incomplete multi-byte sequence (prepended to the next token's bytes). This
    /// is what prevents `�` when a character spans token boundaries.
    static func splitValidUTF8(_ buf: [UInt8]) -> (text: String, rest: [UInt8]) {
        guard !buf.isEmpty else { return ("", []) }
        // Walk back over UTF-8 continuation bytes (0b10xxxxxx) to the last lead byte.
        var i = buf.count - 1
        while i > 0 && (buf[i] & 0xC0) == 0x80 { i -= 1 }
        let lead = buf[i]
        let seqLen: Int
        if lead < 0x80 { seqLen = 1 }
        else if lead & 0xE0 == 0xC0 { seqLen = 2 }
        else if lead & 0xF0 == 0xE0 { seqLen = 3 }
        else if lead & 0xF8 == 0xF0 { seqLen = 4 }
        else { seqLen = 1 }   // stray continuation / invalid lead byte
        if buf.count - i >= seqLen {
            return (String(decoding: buf, as: UTF8.self), [])   // last sequence complete
        }
        return (String(decoding: buf[0..<i], as: UTF8.self), Array(buf[i...]))   // hold remainder
    }
}
