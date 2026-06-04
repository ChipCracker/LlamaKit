//
//  ModelCatalog.swift
//  Registry of downloadable models. Ships the two built-in Qwen3.5 families and
//  lets consumers register their own specs.
//
import Foundation

public final class ModelCatalog: @unchecked Sendable {
    public static let shared = ModelCatalog()

    private let lock = NSLock()
    private var order: [String] = []
    private var byID: [String: ModelSpec] = [:]

    public init(_ specs: [ModelSpec] = ModelCatalog.builtins) {
        register(contentsOf: specs)
    }

    // MARK: Registration

    public func register(_ spec: ModelSpec) {
        lock.lock(); defer { lock.unlock() }
        if byID[spec.id] == nil { order.append(spec.id) }
        byID[spec.id] = spec
    }

    public func register(contentsOf specs: [ModelSpec]) {
        for s in specs { register(s) }
    }

    public func spec(id: String) -> ModelSpec? {
        lock.lock(); defer { lock.unlock() }
        return byID[id]
    }

    /// All registered specs in insertion order.
    public var all: [ModelSpec] {
        lock.lock(); defer { lock.unlock() }
        return order.compactMap { byID[$0] }
    }

    /// Groups registered specs by a string key (e.g. `\.sizeLabel`, `\.family`),
    /// preserving first-seen order of both groups and members.
    public func grouped(by keyPath: KeyPath<ModelSpec, String>) -> [(key: String, specs: [ModelSpec])] {
        var keys: [String] = []
        var buckets: [String: [ModelSpec]] = [:]
        for spec in all {
            let k = spec[keyPath: keyPath]
            if buckets[k] == nil { keys.append(k) }
            buckets[k, default: []].append(spec)
        }
        return keys.map { ($0, buckets[$0] ?? []) }
    }

    // MARK: Built-in Qwen3.5 models

    /// Qwen3.5 0.8B · Q4_0 (ggml-org) — smallest, fastest; the recommended default.
    public static let qwen35_0_8B_Q4_0 = ModelSpec.huggingFace(
        id: "qwen3.5-0.8b-q4_0", displayName: "Q4_0", family: "Qwen3.5", sizeLabel: "0.8B",
        quantization: .q4_0, repo: "ggml-org/Qwen3.5-0.8B-GGUF",
        fileName: "Qwen3.5-0.8B-Q4_0.gguf", approxBytes: 500 * 1_000_000,
        subtitle: "~0.5 GB · fastest, recommended")

    public static let qwen35_0_8B_Q8_0 = ModelSpec.huggingFace(
        id: "qwen3.5-0.8b-q8_0", displayName: "Q8_0", family: "Qwen3.5", sizeLabel: "0.8B",
        quantization: .q8_0, repo: "ggml-org/Qwen3.5-0.8B-GGUF",
        fileName: "Qwen3.5-0.8B-Q8_0.gguf", approxBytes: 900 * 1_000_000,
        subtitle: "~0.9 GB · near-lossless")

    public static let qwen35_0_8B_BF16 = ModelSpec.huggingFace(
        id: "qwen3.5-0.8b-bf16", displayName: "BF16", family: "Qwen3.5", sizeLabel: "0.8B",
        quantization: .bf16, repo: "ggml-org/Qwen3.5-0.8B-GGUF",
        fileName: "Qwen3.5-0.8B-BF16.gguf", approxBytes: 1_600 * 1_000_000,
        subtitle: "~1.6 GB · full precision")

    public static let qwen35_2B_Q4_0 = ModelSpec.huggingFace(
        id: "qwen3.5-2b-q4_0", displayName: "Q4_0", family: "Qwen3.5", sizeLabel: "2B",
        quantization: .q4_0, repo: "unsloth/Qwen3.5-2B-GGUF",
        fileName: "Qwen3.5-2B-Q4_0.gguf", approxBytes: 1_210 * 1_000_000,
        subtitle: "~1.2 GB · more accurate, more RAM")

    public static let qwen35_2B_Q8_0 = ModelSpec.huggingFace(
        id: "qwen3.5-2b-q8_0", displayName: "Q8_0", family: "Qwen3.5", sizeLabel: "2B",
        quantization: .q8_0, repo: "unsloth/Qwen3.5-2B-GGUF",
        fileName: "Qwen3.5-2B-Q8_0.gguf", approxBytes: 2_010 * 1_000_000,
        subtitle: "~2.0 GB · most accurate 2B")

    /// All built-in specs (registered by default).
    public static let builtins: [ModelSpec] = [
        qwen35_0_8B_Q4_0, qwen35_0_8B_Q8_0, qwen35_0_8B_BF16,
        qwen35_2B_Q4_0, qwen35_2B_Q8_0,
    ]

    /// Recommended default for mobile devices.
    public static let recommended = qwen35_0_8B_Q4_0
}
