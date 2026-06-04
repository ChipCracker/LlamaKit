import XCTest
@testable import LlamaKit

final class ModelCatalogTests: XCTestCase {
    func testBuiltinURLsAndMetadata() {
        let spec = ModelCatalog.qwen35_0_8B_Q4_0
        XCTAssertEqual(spec.fileName, "Qwen3.5-0.8B-Q4_0.gguf")
        XCTAssertEqual(spec.downloadURL.absoluteString,
                       "https://huggingface.co/ggml-org/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_0.gguf?download=true")
        XCTAssertEqual(spec.family, "Qwen3.5")
        XCTAssertEqual(spec.sizeLabel, "0.8B")
        XCTAssertEqual(ModelCatalog.recommended.id, "qwen3.5-0.8b-q4_0")
    }

    func testDefaultCatalogHasFiveBuiltins() {
        let catalog = ModelCatalog()            // fresh, not the shared singleton
        XCTAssertEqual(catalog.all.count, 5)
        XCTAssertNotNil(catalog.spec(id: "qwen3.5-2b-q8_0"))
    }

    func testRegisterCustomModel() {
        let catalog = ModelCatalog()
        let custom = ModelSpec.huggingFace(
            id: "llama3.2-1b-q4", displayName: "Q4_K_M", family: "Llama 3.2", sizeLabel: "1B",
            quantization: .q4_k_m, repo: "bartowski/Llama-3.2-1B-Instruct-GGUF",
            fileName: "Llama-3.2-1B-Instruct-Q4_K_M.gguf", approxBytes: 800 * 1_000_000)
        catalog.register(custom)
        XCTAssertEqual(catalog.all.count, 6)
        XCTAssertEqual(catalog.spec(id: "llama3.2-1b-q4")?.displayName, "Q4_K_M")
    }

    func testGroupingBySize() {
        let catalog = ModelCatalog()
        let groups = catalog.grouped(by: \.sizeLabel)
        XCTAssertEqual(groups.map(\.key), ["0.8B", "2B"])
        XCTAssertEqual(groups.first(where: { $0.key == "0.8B" })?.specs.count, 3)
        XCTAssertEqual(groups.first(where: { $0.key == "2B" })?.specs.count, 2)
    }
}
