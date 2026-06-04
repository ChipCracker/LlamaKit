//
//  GenerationStats.swift
//
import Foundation

/// Statistics for one generation run.
public struct GenerationStats: Sendable {
    public var promptTokens: Int
    public var generatedTokens: Int
    public var promptSeconds: Double      // time spent on the prompt prefill
    public var generationSeconds: Double  // time spent generating tokens

    public init(promptTokens: Int = 0,
                generatedTokens: Int = 0,
                promptSeconds: Double = 0,
                generationSeconds: Double = 0) {
        self.promptTokens = promptTokens
        self.generatedTokens = generatedTokens
        self.promptSeconds = promptSeconds
        self.generationSeconds = generationSeconds
    }

    /// Decode speed (tokens per second) of the generation phase.
    public var tokensPerSecond: Double {
        generationSeconds > 0 ? Double(generatedTokens) / generationSeconds : 0
    }
}
