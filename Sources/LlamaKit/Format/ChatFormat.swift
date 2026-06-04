//
//  ChatFormat.swift
//  Pluggable prompt + tool-call format so different model families can be used
//  with the same engine. The default is `Qwen35ChatFormat`.
//
import Foundation

/// A parsed tool call extracted from generated text.
public struct ParsedToolCall: Sendable, Equatable {
    public let name: String
    public let arguments: [String: String]

    public init(name: String, arguments: [String: String]) {
        self.name = name
        self.arguments = arguments
    }
}

/// Describes how prompts are built and how tool calls are recognised/parsed for
/// a given model family. All prefill / KV-cache / context-window mechanics stay
/// in `LlamaEngine`; only the *textual* protocol lives here.
public protocol ChatFormat: Sendable {
    /// Builds the full prompt string (with optional tools + thinking flag),
    /// ending at the assistant generation point.
    func buildPrompt(history: [ChatTurn], thinking: Bool, tools: [LLMTool]) -> String

    /// Text the engine injects into the visible stream as part of the prompt
    /// (e.g. the open `<think>\n` block when thinking is enabled). `nil` if none.
    func thinkingPrefill(thinking: Bool) -> String?

    /// Substring whose appearance ends a generation round to attempt a tool
    /// parse (Qwen3.5: `</tool_call>`). `nil` disables tool calling.
    var toolCallTerminator: String? { get }

    /// Everything *before* this marker is user-visible; the raw tool-call markup
    /// after it is hidden from the stream (Qwen3.5: `<tool_call>`). `nil` shows all.
    var visibleBoundaryMarker: String? { get }

    /// Parses a tool call out of generated text, or `nil` if none/unparseable.
    func parseToolCall(_ text: String) -> ParsedToolCall?

    /// Wraps a tool result as the next history turn(s) before re-generating.
    func toolResultTurns(forAssistant raw: String, result: String, thinking: Bool) -> [ChatTurn]
}

/// Type-erased `ChatFormat` so value types (e.g. `ModelSpec`) can carry a format.
public struct AnyChatFormat: ChatFormat {
    private let base: any ChatFormat

    public init(_ base: some ChatFormat) { self.base = base }

    /// Default format: Qwen3.5 ChatML with `<think>` control + `<tool_call>` XML.
    public static let qwen35 = AnyChatFormat(Qwen35ChatFormat())

    public func buildPrompt(history: [ChatTurn], thinking: Bool, tools: [LLMTool]) -> String {
        base.buildPrompt(history: history, thinking: thinking, tools: tools)
    }
    public func thinkingPrefill(thinking: Bool) -> String? { base.thinkingPrefill(thinking: thinking) }
    public var toolCallTerminator: String? { base.toolCallTerminator }
    public var visibleBoundaryMarker: String? { base.visibleBoundaryMarker }
    public func parseToolCall(_ text: String) -> ParsedToolCall? { base.parseToolCall(text) }
    public func toolResultTurns(forAssistant raw: String, result: String, thinking: Bool) -> [ChatTurn] {
        base.toolResultTurns(forAssistant: raw, result: result, thinking: thinking)
    }
}
