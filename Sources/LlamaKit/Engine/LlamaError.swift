//
//  LlamaError.swift
//
import Foundation

public enum LlamaError: Error, LocalizedError, Sendable {
    case modelLoadFailed(String)
    case contextInitFailed
    case downloadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path): return "Failed to load model: \(path)"
        case .contextInitFailed:         return "Failed to create llama context."
        case .downloadFailed(let msg):   return "Model download failed: \(msg)"
        }
    }
}
