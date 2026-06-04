//
//  llamakit-cli
//  Minimal macOS verification tool for LlamaKit:
//    swift run llamakit-cli --model /path/to/model.gguf --prompt "Hello" [--think] [--tools]
//
import Foundation
import LlamaKit
import LlamaKitTools

func argValue(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
func flag(_ name: String) -> Bool { CommandLine.arguments.contains(name) }

func err(_ s: String) { FileHandle.standardError.write(Data(s.utf8)) }
func out(_ s: String) { FileHandle.standardOutput.write(Data(s.utf8)) }

guard let modelPath = argValue("--model") else {
    err("""
    usage: llamakit-cli --model <model.gguf> [--prompt "..."] [--think] [--tools]
                        [--ctx 4096] [--ngl 999] [--temp 0.7]
    """ + "\n")
    exit(1)
}

let prompt = argValue("--prompt") ?? "Briefly: what is llama.cpp?"
let thinking = flag("--think")
let useTools = flag("--tools")
let ctx = Int(argValue("--ctx") ?? "") ?? 4096
let ngl = Int32(argValue("--ngl") ?? "") ?? LlamaEngine.preferredNGpuLayers
let temp = Float(argValue("--temp") ?? "") ?? 0.7

do {
    err("Loading \(modelPath) (ngl=\(ngl), ctx=\(ctx)) …\n")
    let engine = try await LlamaEngine.make(modelPath: modelPath, nGpuLayers: ngl, contextLength: ctx)

    let history = [
        ChatTurn(role: .system, content: "You are a helpful assistant."),
        ChatTurn(role: .user, content: prompt),
    ]
    let tools: [LLMTool] = useTools ? [.calculator, .webSearch] : []
    let options = GenerationOptions(sampling: temp <= 0 ? .greedy : SamplingParams(temperature: temp),
                                    thinking: thinking, maxTokens: 512)

    let stats = await engine.generate(
        history: history, tools: tools, options: options,
        onToken: { out($0) },
        onTool: { inv in err("\n[tool] \(inv.name)(\(inv.argumentSummary)) = \(inv.result)\n") })

    err(String(format: "\n--- %d tokens · %.1f tok/s · prompt %d (%.0f ms prefill) ---\n",
               stats.generatedTokens, stats.tokensPerSecond, stats.promptTokens, stats.promptSeconds * 1000))
} catch {
    err("Error: \(error.localizedDescription)\n")
    exit(2)
}
