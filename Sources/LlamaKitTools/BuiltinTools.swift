//
//  BuiltinTools.swift
//  Ready-to-use `LLMTool` values. Compose them into `generate(tools:)`, e.g.
//  `[.calculator, .webSearch, myCustomTool]`.
//
import Foundation
import LlamaKit

extension LLMTool {
    /// Arithmetic calculator (safe Shunting-Yard parser, see `Calculator`).
    public static let calculator = LLMTool(
        name: "calculate",
        jsonSchema: #"{"type": "function", "function": {"name": "calculate", "description": "Evaluates an arithmetic expression (e.g. (3+4)*2, 1234*5678, 2^10) and returns the exact result. Use this tool for ANY calculation instead of computing it yourself.", "parameters": {"type": "object", "properties": {"expression": {"type": "string", "description": "The arithmetic expression. Allowed: + - * / % ^ ( ) and numbers."}}, "required": ["expression"]}}}"#,
        run: { args in
            guard let expr = args["expression"], !expr.isEmpty else {
                return "Error: no expression provided"
            }
            return Calculator.evaluate(expr)
        })

    /// Web search via DuckDuckGo (no API key). Sends the query to a third party →
    /// breaks the "fully offline" property.
    public static let webSearch = LLMTool(
        name: "web_search",
        jsonSchema: #"{"type": "function", "function": {"name": "web_search", "description": "Searches the web (DuckDuckGo) and returns real result snippets with URLs. Use this for facts, people, places, current events or anything you are not certain about. Base your answer on the returned results and cite the source URL when helpful.", "parameters": {"type": "object", "properties": {"query": {"type": "string", "description": "Concise, keyword-focused search query (drop filler words). Use the language that best matches the expected sources."}}, "required": ["query"]}}}"#,
        run: { args in
            guard let query = args["query"], !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                return "Error: no search query provided"
            }
            return await WebSearch.run(query: query)
        })
}
