import XCTest
import LlamaKit
import LlamaKitTools

/// Heavy end-to-end tests. Skipped unless LLAMAKIT_RUN_INTEGRATION=1 (they
/// download ~500 MB and run real inference). On macOS they use Metal/CPU.
private final class TextBox: @unchecked Sendable {
    private let lock = NSLock()
    private var s = ""
    func add(_ x: String) { lock.lock(); s += x; lock.unlock() }
    var value: String { lock.lock(); defer { lock.unlock() }; return s }
}

final class IntegrationTests: XCTestCase {

    private func ensureModel() async throws -> URL {
        let spec = ModelCatalog.recommended
        let downloader = ModelDownloader()
        if downloader.isDownloaded(spec) { return downloader.localURL(for: spec) }
        return try await downloader.download(spec) { p in
            if Int(p * 100) % 10 == 0 { FileHandle.standardError.write(Data("\rdownload \(Int(p*100))%".utf8)) }
        }
    }

    func testGeneratesText() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LLAMAKIT_RUN_INTEGRATION"] == "1",
                          "set LLAMAKIT_RUN_INTEGRATION=1 to run")
        let url = try await ensureModel()
        let engine = try await LlamaEngine.make(spec: ModelCatalog.recommended, downloadedAt: url, nGpuLayers: 999)
        let text = TextBox()
        let stats = await engine.generate(
            history: [.init(role: .system, content: "You are a helpful assistant."),
                      .init(role: .user, content: "Say hello in one short sentence.")],
            options: .init(sampling: .greedy, maxTokens: 64),
            onToken: { text.add($0) })
        XCTAssertGreaterThan(stats.generatedTokens, 0)
        XCTAssertFalse(text.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testCalculatorToolLoop() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LLAMAKIT_RUN_INTEGRATION"] == "1",
                          "set LLAMAKIT_RUN_INTEGRATION=1 to run")
        let url = try await ensureModel()
        let engine = try await LlamaEngine.make(spec: ModelCatalog.recommended, downloadedAt: url, nGpuLayers: 999)

        actor Box { var calls: [ToolInvocation] = []; func add(_ c: ToolInvocation) { calls.append(c) } }
        let box = Box()
        _ = await engine.generate(
            history: [.init(role: .system, content: "You are a helpful assistant."),
                      .init(role: .user, content: "What is 1234 multiplied by 5678?")],
            tools: [.calculator],
            options: .init(sampling: .greedy, maxTokens: 256),
            onToken: { _ in },
            onTool: { inv in Task { await box.add(inv) } })

        // Give the detached add() tasks a moment to drain.
        try await Task.sleep(nanoseconds: 200_000_000)
        let calls = await box.calls
        XCTAssertTrue(calls.contains { $0.name == "calculate" && $0.result == "7006652" },
                      "expected a calculate(1234*5678)=7006652 tool call; got \(calls)")
    }
}
