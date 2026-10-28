import Foundation
import LlamaSwift
import os

private let logger = Logger(subsystem: "com.volocal.app", category: "llm")

/// Manages LLM inference using llama.cpp via the LlamaContext actor.
@MainActor
final class LLMManager: ObservableObject {
    @Published var response: String = ""
    @Published var isGenerating: Bool = false
    @Published var error: String?
    @Published var tokensPerSecond: Double = 0

    private var llamaContext: LlamaContext?
    private var generationTask: Task<Void, Never>?
    private let memoryStore: MemoryStore

    private static let baseSystemPrompt = """
    You are Volocal, a helpful voice assistant running entirely on-device. \
    Keep responses concise and conversational — typically 1-3 sentences. \
    You're speaking out loud, so avoid markdown, code blocks, or lists. \
    Be friendly, direct, and natural.
    """

    /// Loads `memory.pbmem` before any prompt is built.
    init(memoryStore: MemoryStore = MemoryStore()) {
        self.memoryStore = memoryStore
    }

    /// Finalized user transcript. Heuristic extraction only; nothing is sent back through the model.
    func recordUserTurn(_ text: String) {
        memoryStore.ingest(userUtterance: text)
    }

    func wipeMemory() {
        memoryStore.wipe()
    }

    func loadModel(path: String) async throws {
        // Context 2048 and F16 K/V (latency A/B step 1, matches upstream).
        llamaContext = try LlamaContext.create(
            path: path,
            contextSize: 2048,
            kvCacheType: GGML_TYPE_F16
        )
    }

    /// Generate response from conversation history.
    /// History should already contain the latest user message.
    func generate(history: [ConversationMessage] = []) -> AsyncStream<String> {
        // Cancel any previous generation first
        generationTask?.cancel()
        generationTask = nil

        // ChatML matching Qwen/Qwen3.5-2B's chat_template.jinja.
        // Past assistant turns are plain text (no empty think blocks).
        // Memory is already loaded (and any fact from this turn already stored).
        let systemPrompt = makeSystemPrompt()
        var fullPrompt = "<|im_start|>system\n\(systemPrompt)<|im_end|>\n"
        for message in history {
            let role = message.role == .user ? "user" : "assistant"
            fullPrompt += "<|im_start|>\(role)\n\(message.text)<|im_end|>\n"
        }
        // Official non-thinking generation prompt (enable_thinking=false):
        // <|im_start|>assistant\n<think>\n\n</think>\n\n
        fullPrompt += "<|im_start|>assistant\n<think>\n\n</think>\n\n"

        return AsyncStream { continuation in
            generationTask = Task {
                guard let ctx = llamaContext else {
                    continuation.finish()
                    return
                }

                await MainActor.run {
                    self.isGenerating = true
                    self.response = ""
                    self.tokensPerSecond = 0
                }

                let startTime = CFAbsoluteTimeGetCurrent()
                var tokenCount = 0

                do {
                    await ctx.clear()
                    try await ctx.completionInit(text: fullPrompt)

                    while !Task.isCancelled {
                        guard let token = await ctx.completionLoop() else { break }

                        tokenCount += 1

                        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                        let tps = elapsed > 0 ? Double(tokenCount) / elapsed : 0

                        #if DEBUG
                        let hex = token.utf8.map { String(format: "%02x", $0) }.joined(separator: " ")
                        logger.debug("token[\(tokenCount)]: \"\(token)\" hex=[\(hex)]")
                        #endif

                        // Strip non-ASCII characters
                        let cleaned = String(token.unicodeScalars.filter { $0.isASCII })
                        guard !cleaned.isEmpty else { continue }

                        continuation.yield(cleaned)

                        await MainActor.run {
                            self.response += cleaned
                            self.tokensPerSecond = tps
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.error = error.localizedDescription
                    }
                }

                await MainActor.run {
                    self.isGenerating = false
                }
                continuation.finish()
            }
        }
    }

    private func makeSystemPrompt() -> String {
        MemoryStore.composeSystemPrompt(
            base: Self.baseSystemPrompt,
            memoryBlock: memoryStore.promptBlock()
        )
    }

    func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
    }

    var isModelLoaded: Bool {
        llamaContext != nil
    }
}
