//
//  ModelSpec.swift
//  Open, extensible description of a downloadable GGUF model.
//
//  Replaces the demo's closed `enum ModelVariant`: consumers can register their
//  own models with `ModelCatalog.shared.register(.huggingFace(...))`.
//
import Foundation

public enum Quantization: Sendable, Hashable {
    case q4_0, q4_k_m, q5_k_m, q6_k, q8_0, bf16, f16
    case custom(String)

    public var label: String {
        switch self {
        case .q4_0:  return "Q4_0"
        case .q4_k_m: return "Q4_K_M"
        case .q5_k_m: return "Q5_K_M"
        case .q6_k:  return "Q6_K"
        case .q8_0:  return "Q8_0"
        case .bf16:  return "BF16"
        case .f16:   return "F16"
        case .custom(let s): return s
        }
    }
}

public struct ModelSpec: Sendable, Identifiable, Hashable {
    /// Stable key (e.g. "qwen3.5-0.8b-q4_0"). Used as the catalog/registry key.
    public let id: String
    /// Quant short label for UIs (e.g. "Q4_0").
    public let displayName: String
    /// Family/group label for UI grouping (e.g. "Qwen3.5").
    public let family: String
    /// Size label for UI grouping (e.g. "0.8B").
    public let sizeLabel: String
    public let quantization: Quantization
    /// Destination filename on disk (must be unique within a download directory).
    public let fileName: String
    /// Rough byte size for progress UIs when the server omits Content-Length.
    public let approxBytes: Int64
    /// Optional UI hint (consumer-supplied / localised by the consumer).
    public let subtitle: String?
    public let downloadURL: URL
    /// Chat/prompt format the weights expect (default Qwen3.5). Carried so that
    /// `LlamaEngine.make(spec:downloadedAt:)` always wires the right template.
    public let chatFormat: AnyChatFormat

    public init(id: String,
                displayName: String,
                family: String,
                sizeLabel: String,
                quantization: Quantization,
                fileName: String,
                approxBytes: Int64,
                subtitle: String? = nil,
                downloadURL: URL,
                chatFormat: AnyChatFormat = .qwen35) {
        self.id = id
        self.displayName = displayName
        self.family = family
        self.sizeLabel = sizeLabel
        self.quantization = quantization
        self.fileName = fileName
        self.approxBytes = approxBytes
        self.subtitle = subtitle
        self.downloadURL = downloadURL
        self.chatFormat = chatFormat
    }

    /// Builds a spec from a Hugging Face repo + filename
    /// (`https://huggingface.co/<repo>/resolve/main/<file>?download=true`).
    public static func huggingFace(id: String,
                                   displayName: String,
                                   family: String,
                                   sizeLabel: String,
                                   quantization: Quantization,
                                   repo: String,
                                   fileName: String,
                                   approxBytes: Int64,
                                   subtitle: String? = nil,
                                   chatFormat: AnyChatFormat = .qwen35) -> ModelSpec {
        let url = URL(string: "https://huggingface.co/\(repo)/resolve/main/\(fileName)?download=true")!
        return ModelSpec(id: id, displayName: displayName, family: family, sizeLabel: sizeLabel,
                         quantization: quantization, fileName: fileName, approxBytes: approxBytes,
                         subtitle: subtitle, downloadURL: url, chatFormat: chatFormat)
    }

    // Identity is the stable `id` (so re-registration / format tweaks don't break keys).
    public static func == (lhs: ModelSpec, rhs: ModelSpec) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
