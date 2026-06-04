//
//  GenerationOptions.swift
//
import Foundation

/// Tunables for a single `generate(...)` call.
public struct GenerationOptions: Sendable {
    public var sampling: SamplingParams
    /// Qwen3.5-style visible reasoning (`<think>…</think>`). See `ChatFormat`.
    public var thinking: Bool
    /// Hard cap on generated tokens (the context window is the other bound).
    public var maxTokens: Int
    /// Safety cap on tool-call rounds (prevents infinite tool loops).
    public var maxToolRounds: Int

    public init(sampling: SamplingParams = SamplingParams(),
                thinking: Bool = false,
                maxTokens: Int = 1024,
                maxToolRounds: Int = 5) {
        self.sampling = sampling
        self.thinking = thinking
        self.maxTokens = maxTokens
        self.maxToolRounds = maxToolRounds
    }
}

/// Event emitted by the `AsyncStream` generation variant.
public enum GenerationEvent: Sendable {
    case token(String)
    case tool(ToolInvocation)
    case finished(GenerationStats)
}
