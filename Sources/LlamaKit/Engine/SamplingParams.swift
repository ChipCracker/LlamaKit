//
//  SamplingParams.swift
//
import Foundation

/// Sampling parameters (classic top-k / top-p / min-p / temperature, plus a
/// greedy option). `temperature <= 0` selects deterministic argmax sampling.
public struct SamplingParams: Sendable {
    public var temperature: Float
    public var topK: Int32
    public var topP: Float
    public var minP: Float
    public var seed: UInt32   // 0xFFFFFFFF == LLAMA_DEFAULT_SEED (random)

    public init(temperature: Float = 0.7,
                topK: Int32 = 40,
                topP: Float = 0.95,
                minP: Float = 0.05,
                seed: UInt32 = 0xFFFFFFFF) {
        self.temperature = temperature
        self.topK = topK
        self.topP = topP
        self.minP = minP
        self.seed = seed
    }

    /// Deterministic (argmax) sampling.
    public static let greedy = SamplingParams(temperature: 0)
}
