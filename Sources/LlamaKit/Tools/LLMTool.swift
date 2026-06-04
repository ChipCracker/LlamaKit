//
//  LLMTool.swift
//  Generic tool abstraction for native function/tool calling.
//
//  A tool is its JSON schema (injected verbatim into the prompt's `<tools>`
//  block) plus an async `run` closure that receives the parsed arguments and
//  returns a result string. Define new tools as additional `LLMTool` values and
//  pass them to `LlamaEngine.generate(tools:)`. Built-in example tools
//  (calculator, web search) live in the `LlamaKitTools` product.
//
import Foundation

/// A tool the model may call.
public struct LLMTool: Sendable {
    /// Function name, exactly as in the JSON schema (`"name"`).
    public let name: String
    /// Full JSON schema of the function (OpenAI function-calling format).
    public let jsonSchema: String
    /// Executes the tool with the parsed `<parameter=…>` arguments. `async` so
    /// network-backed tools are possible; purely synchronous tools satisfy it
    /// without extra work.
    public let run: @Sendable (_ args: [String: String]) async -> String

    public init(name: String,
                jsonSchema: String,
                run: @escaping @Sendable (_ args: [String: String]) async -> String) {
        self.name = name
        self.jsonSchema = jsonSchema
        self.run = run
    }
}

/// A concrete tool call and its result — surfaced via stream events / callbacks.
public struct ToolInvocation: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let arguments: [String: String]
    public let result: String

    public init(id: UUID = UUID(),
                name: String,
                arguments: [String: String],
                result: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.result = result
    }

    /// Compact argument display for UIs. For a single argument just the value
    /// (e.g. `(3+4)*2`), otherwise sorted `key=value` pairs.
    public var argumentSummary: String {
        if arguments.count == 1, let only = arguments.first { return only.value }
        return arguments.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
    }
}
