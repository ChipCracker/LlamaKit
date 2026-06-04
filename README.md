# LlamaKit

A small, reusable Swift Package for **on-device LLM inference with llama.cpp**.
It wraps the `llama.xcframework` and provides clean, framework-agnostic APIs for:

- **Context-window management** — chunked prefill (≤ `n_batch`), per-turn KV reset, token + context-overflow bounds.
- **Tool calling** — a native agent loop (`<tool_call>` XML, `# Tools` system block, multi-round) with extensible `LLMTool`s.
- **Model download** — an extensible catalog (2 built-in Qwen3.5 families + register your own) and a SwiftUI-free downloader.

Drop it into any iOS / macOS / tvOS / visionOS app via SPM.

## Install

```swift
.package(url: "https://github.com/ChipCracker/LlamaKit.git", from: "1.0.0")
// targets: .product(name: "LlamaKit", package: "LlamaKit"),
//          .product(name: "LlamaKitTools", package: "LlamaKit")  // optional built-in tools
```

The `llama.xcframework` ships as a stripped release zip (`url:`+`checksum:`); SPM downloads + caches it once. For local development the package builds against the in-tree `Frameworks/llama.xcframework` (see *Building the xcframework*).

## Quick start

```swift
import LlamaKit
import LlamaKitTools   // for .calculator / .webSearch

// 1) Download a model (progress via AsyncStream or callback).
let spec = ModelCatalog.recommended            // Qwen3.5 0.8B Q4_0
let downloader = ModelDownloader()
let url = try await downloader.download(spec) { p in print("download \(Int(p*100))%") }

// 2) Load the engine (chat format is taken from the spec).
let engine = try await LlamaEngine.make(spec: spec, downloadedAt: url)

// 3) Generate — streaming tokens + tool calls.
let history = [
    ChatTurn(role: .system, content: "You are a helpful assistant."),
    ChatTurn(role: .user,   content: "What is 1234 * 5678?"),
]
let stats = await engine.generate(
    history: history,
    tools: [.calculator],                       // optional
    options: .init(thinking: false, maxTokens: 512),
    onToken: { print($0, terminator: "") },
    onTool:  { inv in print("\n[tool] \(inv.name) = \(inv.result)") })
print("\n\(stats.generatedTokens) tokens, \(stats.tokensPerSecond) tok/s")
```

Or use the `AsyncStream` variant:

```swift
for await event in engine.generate(history: history, tools: [.calculator]) {
    switch event {
    case .token(let t): print(t, terminator: "")
    case .tool(let inv): print("\n[tool] \(inv.name) = \(inv.result)")
    case .finished(let stats): print("\n\(stats.tokensPerSecond) tok/s")
    }
}
```

## Custom models & tools

```swift
// Register any GGUF (extensible catalog):
ModelCatalog.shared.register(.huggingFace(
    id: "llama3.2-1b-q4", displayName: "Q4_K_M", family: "Llama 3.2", sizeLabel: "1B",
    quantization: .q4_k_m, repo: "bartowski/Llama-3.2-1B-Instruct-GGUF",
    fileName: "Llama-3.2-1B-Instruct-Q4_K_M.gguf", approxBytes: 800_000_000,
    chatFormat: .qwen35))   // or a custom ChatFormat for non-Qwen families

// Define a custom tool:
let timeTool = LLMTool(
    name: "current_time",
    jsonSchema: #"{"type":"function","function":{"name":"current_time","description":"Returns the current time.","parameters":{"type":"object","properties":{},"required":[]}}}"#,
    run: { _ in ISO8601DateFormatter().string(from: Date()) })

await engine.generate(history: history, tools: [.calculator, timeTool], onToken: { ... })
```

`ChatFormat` is pluggable (default `Qwen35ChatFormat`); a model's prompt/tool-call
format travels with its `ModelSpec`, so you can't accidentally pair weights with
the wrong template.

## Building the xcframework

```bash
bash scripts/build-xcframework.sh        # clones llama.cpp @ b9488, builds Frameworks/llama.xcframework
swift build                              # auto-uses the local xcframework
swift test                               # offline unit tests (Calculator, tool-call parsing, catalog, web-search parse)
LLAMAKIT_RUN_INTEGRATION=1 swift test    # heavy: downloads ~500 MB + runs real inference
swift run llamakit-cli --model ~/Library/Application\ Support/Models/Qwen3.5-0.8B-Q4_0.gguf --prompt "Hi" --tools
```

## Publishing a release (remote SPM)

```bash
bash scripts/build-xcframework.sh
bash scripts/package-xcframework.sh llama-b9488-1     # strips dSYMs, zips, prints url+checksum
# paste the url+checksum into Package.swift, commit, then:
git tag llama-b9488-1 && git push --tags
gh release create llama-b9488-1 dist/llama.xcframework.zip dist/llama.dSYMs.zip
```

The manifest auto-selects: local `Frameworks/llama.xcframework` when present (or
`LLAMAKIT_LOCAL_XCFRAMEWORK=1`), otherwise the remote `url:`+`checksum:` artifact.

## Notes

- Pinned to llama.cpp tag **b9488** (ggml 0.13.x); supports the Qwen3.5 (`qwen35`) hybrid architecture. Bump in `scripts/build-xcframework.sh` and re-check the C symbols in `LlamaEngine.swift`.
- The dynamic xcframework is auto-embedded + re-signed by consuming apps (no manual embed/sign).
- Built-in tools are split into `LlamaKitTools` so the core `LlamaKit` stays offline/dependency-free. `web_search` scrapes DuckDuckGo (ToS grey area, fragile to markup changes) and breaks the offline property.

## License

The wrapper code is yours to license. llama.cpp / ggml are MIT (ggml-org). Models
(e.g. Qwen3.5) carry their own licenses.
