//
//  Qwen35ChatFormat.swift
//  Default chat format: Qwen3.5 ChatML with explicit `<think>` control and the
//  native `<tool_call><function=…>` XML tool-call protocol.
//
//  Why build the prompt manually instead of `llama_chat_apply_template`? The
//  built-in (non-Jinja) Qwen template always appends an empty `<think></think>`
//  to the assistant turn, so thinking can never be enabled through it. Qwen3.5
//  also dropped the Qwen3 `/think` soft switch; thinking is controlled only via
//  the `enable_thinking` hard switch. We reproduce that generation prompt 1:1:
//    thinking OFF → `<|im_start|>assistant\n<think>\n\n</think>\n\n`  (empty block
//                   prefilled → model answers directly)
//    thinking ON  → `<|im_start|>assistant\n<think>\n`               (open block
//                   prefilled → model must reason before `</think>` + the answer)
//
import Foundation

public struct Qwen35ChatFormat: ChatFormat {
    public init() {}

    public func buildPrompt(history: [ChatTurn], thinking: Bool, tools: [LLMTool]) -> String {
        let toolsJSON = tools.isEmpty ? nil : tools.map { $0.jsonSchema }.joined(separator: "\n")
        var out = ""
        for (i, t) in history.enumerated() {
            if i == 0, t.role == .system, let toolsJSON {
                out += "<|im_start|>system\n\(Self.toolsPreamble(toolsJSON))\n\n\(t.content)<|im_end|>\n"
                continue
            }
            let content = t.role == .assistant ? Self.stripThink(t.content) : t.content
            out += "<|im_start|>\(t.role.rawValue)\n\(content)<|im_end|>\n"
        }
        out += "<|im_start|>assistant\n"
        out += thinking ? "<think>\n" : "<think>\n\n</think>\n\n"
        return out
    }

    public func thinkingPrefill(thinking: Bool) -> String? {
        thinking ? "<think>\n" : nil
    }

    public var toolCallTerminator: String? { "</tool_call>" }
    public var visibleBoundaryMarker: String? { "<tool_call>" }

    public func toolResultTurns(forAssistant raw: String, result: String, thinking: Bool) -> [ChatTurn] {
        let assistantContent = (thinking ? "<think>\n" : "") + raw
        return [
            ChatTurn(role: .assistant, content: assistantContent),
            ChatTurn(role: .user, content: "<tool_response>\n\(result)\n</tool_response>"),
        ]
    }

    // MARK: - Tool-call parsing

    /// Parses `<function=name> <parameter=key>value</parameter> …` from text.
    public func parseToolCall(_ s: String) -> ParsedToolCall? {
        guard let fn = s.range(of: "<function="),
              let gt = s.range(of: ">", range: fn.upperBound..<s.endIndex) else { return nil }
        let name = String(s[fn.upperBound..<gt.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var args: [String: String] = [:]
        var cursor = gt.upperBound
        while let pStart = s.range(of: "<parameter=", range: cursor..<s.endIndex),
              let pGt = s.range(of: ">", range: pStart.upperBound..<s.endIndex),
              let pEnd = s.range(of: "</parameter>", range: pGt.upperBound..<s.endIndex) {
            let key = String(s[pStart.upperBound..<pGt.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let val = String(s[pGt.upperBound..<pEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            args[key] = val
            cursor = pEnd.upperBound
        }
        return name.isEmpty ? nil : ParsedToolCall(name: name, arguments: args)
    }

    // MARK: - Helpers

    /// `# Tools` system block in the Qwen3.5 format.
    static func toolsPreamble(_ toolsJSON: String) -> String {
        """
        # Tools

        You have access to the following functions:

        <tools>
        \(toolsJSON)
        </tools>

        If you choose to call a function ONLY reply in the following format with NO suffix:

        <tool_call>
        <function=example_function_name>
        <parameter=example_parameter_1>
        value_1
        </parameter>
        </function>
        </tool_call>

        <IMPORTANT>
        Reminder:
        - Function calls MUST follow the specified format: an inner <function=...></function> block must be nested within <tool_call></tool_call> XML tags
        - Required parameters MUST be specified
        - You may provide optional reasoning for your function call in natural language BEFORE the function call, but NOT after
        - If there is no function call available, answer the question like normal with your current knowledge and do not tell the user about function calls
        </IMPORTANT>
        """
    }

    /// Removes a `<think>…</think>` block (and surrounding whitespace) from a
    /// previous assistant answer.
    static func stripThink(_ s: String) -> String {
        guard let start = s.range(of: "<think>"), let end = s.range(of: "</think>") else {
            return s
        }
        var result = s
        result.removeSubrange(start.lowerBound..<end.upperBound)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
