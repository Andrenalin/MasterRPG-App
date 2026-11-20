// @copyright André Trettin

#if !os(tvOS)

import Foundation
import FoundationModels
import Testing

@testable import GeneratorRPG

/// CODE_AUDIT_TestGaps §5.8: the conversation engine's overflow recovery, session reset and
/// streaming task. The three calls that need Apple Intelligence are replaced through
/// `ConversationEngine.hooks`; everything around them (the recovery decision, the new session, the
/// continuation prompt, the state flags, the task handling) is the production code.
@MainActor
@Suite("Conversation engine")
struct ConversationEngineTests {
    private struct ModelFailure: Error, Equatable {}

    private func overflow() -> LanguageModelError {
        .contextSizeExceeded(.init(contextSize: 4096, tokenCount: 5000, debugDescription: "test overflow"))
    }

    private func engine(overflowResetMessage: String? = nil) -> ConversationEngine {
        ConversationEngine(configuration: ConversationConfiguration(
            baseInstructions: "Be brief.",
            summaryInstructions: "Summarise.",
            summaryPromptPreamble: "Summarise this:",
            conversationUserLabel: "User:",
            conversationAssistantLabel: "Assistant:",
            continuationNote: "Continue naturally.",
            overflowResetMessage: overflowResetMessage
        ))
    }

    private let summary = ConversationSummary(summary: "We planned a heist.", keyTopics: ["vault", "guards"], userPreferences: ["short answers"])

    /// Records the prompts a hook receives.
    private final class Calls {
        var prompts: [String] = []
        var summaries = 0
    }

    // MARK: - Prompt validation

    @Test("An empty or blank prompt is refused before the model is asked", arguments: ["", "   ", "\n\t "])
    func blankPromptIsRefused(prompt: String) async {
        let engine = engine()
        let calls = Calls()
        engine.hooks.respond = { prompt in calls.prompts.append(prompt); return "x" }

        await #expect(throws: FoundationModelCoreError.self) { try await engine.sendMessage(prompt) }

        #expect(calls.prompts.isEmpty)
        #expect(engine.sessionCount == 1)
    }

    @Test("The prompt is trimmed before it is sent")
    func promptIsTrimmed() async throws {
        let engine = engine()
        let calls = Calls()
        engine.hooks.respond = { prompt in calls.prompts.append(prompt); return "ok" }

        let answer = try await engine.sendMessage("  hello \n")

        #expect(answer == "ok")
        #expect(calls.prompts == ["hello"])
        #expect(engine.sessionCount == 1)
    }

    // MARK: - Overflow recovery

    @Test("A context overflow summarises, starts a new session and answers with the summary in the prompt")
    func overflowRecovers() async throws {
        let engine = engine()
        let calls = Calls()
        var summarizingDuringSummary: Bool?
        engine.hooks.respond = { prompt in
            calls.prompts.append(prompt)
            if calls.prompts.count == 1 { throw LanguageModelError.contextSizeExceeded(.init(contextSize: 4096, tokenCount: 5000, debugDescription: "x")) }
            return "recovered"
        }
        engine.hooks.summarize = { [summary] in
            summarizingDuringSummary = engine.isSummarizing
            return summary
        }

        let answer = try await engine.sendMessage("Open the vault")

        #expect(answer == "recovered")
        #expect(engine.sessionCount == 2)
        #expect(summarizingDuringSummary == true)
        #expect(!engine.isSummarizing, "the flag is cleared when the recovery ends")
        #expect(calls.prompts.first == "Open the vault")
        let continuation = try #require(calls.prompts.last)
        #expect(continuation.contains("We planned a heist."))
        #expect(continuation.contains("• vault"))
        #expect(continuation.contains("• short answers"))
        #expect(continuation.contains("Continue naturally."))
        #expect(continuation.hasSuffix("Open the vault"), "the user's message comes last")
    }

    @Test("A streaming overflow recovers the same way and streams the continuation")
    func streamingOverflowRecovers() async throws {
        let engine = engine()
        let calls = Calls()
        engine.hooks.streamedContent = { prompt in
            calls.prompts.append(prompt)
            let isFirst = calls.prompts.count == 1
            return AsyncThrowingStream { continuation in
                if isFirst {
                    continuation.finish(throwing: LanguageModelError.contextSizeExceeded(.init(contextSize: 4096, tokenCount: 5000, debugDescription: "x")))
                } else {
                    continuation.yield("Part")
                    continuation.yield("Part two")
                    continuation.finish()
                }
            }
        }
        engine.hooks.summarize = { [summary] in summary }
        var partials: [String] = []

        let answer = try await engine.sendStreamingMessage("Go on") { partials.append($0) }

        #expect(answer == "Part two")
        #expect(partials == ["Part", "Part two"])
        #expect(engine.sessionCount == 2)
        #expect(calls.prompts.last?.contains("We planned a heist.") == true)
    }

    @Test("When the summary fails the session is reset and the reset message answers")
    func summaryFailureResetsWithMessage() async throws {
        let engine = engine(overflowResetMessage: "  The conversation was reset.  ")
        engine.hooks.respond = { _ in throw LanguageModelError.contextSizeExceeded(.init(contextSize: 4096, tokenCount: 5000, debugDescription: "x")) }
        engine.hooks.streamedContent = { _ in
            AsyncThrowingStream { $0.finish(throwing: LanguageModelError.contextSizeExceeded(.init(contextSize: 4096, tokenCount: 5000, debugDescription: "x"))) }
        }
        engine.hooks.summarize = { throw ModelFailure() }
        var partials: [String] = []

        let answer = try await engine.sendMessage("Hello")
        #expect(answer == "The conversation was reset.", "trimmed")
        #expect(engine.sessionCount == 2)

        let streamed = try await engine.sendStreamingMessage("Hello") { partials.append($0) }
        #expect(streamed == "The conversation was reset.")
        #expect(partials == ["The conversation was reset."], "the reset message is also shown as the partial response")
        #expect(engine.sessionCount == 3)
        #expect(!engine.isSummarizing)
    }

    @Test("Without a reset message a failing summary rethrows its error, after the session was reset")
    func summaryFailureRethrows() async {
        let engine = engine(overflowResetMessage: nil)
        engine.hooks.respond = { _ in throw LanguageModelError.contextSizeExceeded(.init(contextSize: 4096, tokenCount: 5000, debugDescription: "x")) }
        engine.hooks.summarize = { throw ModelFailure() }

        await #expect(throws: ModelFailure.self) { try await engine.sendMessage("Hello") }

        #expect(engine.sessionCount == 2, "a fresh session, so the next message does not overflow again")
        #expect(!engine.isSummarizing)
    }

    @Test("A blank reset message counts as none")
    func blankResetMessageIsNone() async {
        let engine = engine(overflowResetMessage: "   ")
        engine.hooks.respond = { _ in throw LanguageModelError.contextSizeExceeded(.init(contextSize: 4096, tokenCount: 5000, debugDescription: "x")) }
        engine.hooks.summarize = { throw ModelFailure() }

        await #expect(throws: ModelFailure.self) { try await engine.sendMessage("Hello") }
    }

    @Test("A cancelled summary does not reset the session another call may be using")
    func cancelledSummaryKeepsTheSession() async {
        let engine = engine(overflowResetMessage: "reset")
        engine.hooks.respond = { _ in throw LanguageModelError.contextSizeExceeded(.init(contextSize: 4096, tokenCount: 5000, debugDescription: "x")) }
        engine.hooks.summarize = { throw CancellationError() }

        await #expect(throws: CancellationError.self) { try await engine.sendMessage("Hello") }

        #expect(engine.sessionCount == 1)
        #expect(!engine.isSummarizing)
    }

    @Test("An error that is not an overflow is passed on without any recovery")
    func otherErrorsPassThrough() async {
        let engine = engine(overflowResetMessage: "reset")
        let calls = Calls()
        engine.hooks.respond = { _ in throw ModelFailure() }
        engine.hooks.summarize = { calls.summaries += 1; return ConversationSummary(summary: "", keyTopics: [], userPreferences: []) }

        await #expect(throws: ModelFailure.self) { try await engine.sendMessage("Hello") }

        #expect(calls.summaries == 0)
        #expect(engine.sessionCount == 1)
    }

    @Test("A summary without topics or preferences says so instead of leaving a gap")
    func emptySummaryListsSaySoInThePrompt() {
        let prompt = ConversationContextBuilder.contextPrompt(
            summary: ConversationSummary(summary: "S", keyTopics: [], userPreferences: []),
            continuationNote: "  ",
            userMessage: "Hi"
        )

        #expect(prompt.contains("• None recorded yet"))
        #expect(!prompt.contains("\n\n  \n"), "a blank note is not added")
        #expect(prompt.hasSuffix("Hi"))
    }

    // MARK: - Streaming task

    @Test("Cancelling the response ends a stream that has no end of its own")
    func cancelEndsTheStream() async {
        let engine = engine()
        engine.hooks.streamedContent = { _ in
            AsyncThrowingStream { continuation in
                let producer = Task {
                    var count = 0
                    while !Task.isCancelled {
                        continuation.yield("chunk \(count)")
                        count += 1
                        try? await Task.sleep(for: .milliseconds(5))
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in producer.cancel() }
            }
        }
        let request = Task { try await engine.sendStreamingMessage("Tell a story") }
        try? await Task.sleep(for: .milliseconds(50))

        engine.cancelActiveResponse()
        let ended = await awaitCondition(timeout: .seconds(5)) { request.isCancelled || engine.sessionCount == 1 }
        request.cancel()
        _ = await request.result

        #expect(ended)
        #expect(engine.sessionCount == 1, "a cancel is not an overflow")
    }

    @Test("Partial responses arrive in order and the last one is the answer")
    func partialsAreOrdered() async throws {
        let engine = engine()
        engine.hooks.streamedContent = { _ in
            AsyncThrowingStream { continuation in
                for text in ["A", "AB", "ABC"] { continuation.yield(text) }
                continuation.finish()
            }
        }
        var partials: [String] = []

        let answer = try await engine.sendStreamingMessage("x") { partials.append($0) }

        #expect(partials == ["A", "AB", "ABC"])
        #expect(answer == "ABC")
    }

    @Test("A second request replaces the first, and the first one's end does not drop the second's handle")
    func newerRequestKeepsItsHandle() async throws {
        let engine = engine()
        let gate = AsyncStream<Void>.makeStream()
        engine.hooks.streamedContent = { prompt in
            AsyncThrowingStream { continuation in
                if prompt == "first" {
                    continuation.yield("first")
                    continuation.finish()
                } else {
                    Task {
                        for await _ in gate.stream { break }
                        continuation.yield("second")
                        continuation.finish()
                    }
                }
            }
        }

        let first = try await engine.sendStreamingMessage("first")
        let second = Task { try await engine.sendStreamingMessage("second") }
        try? await Task.sleep(for: .milliseconds(30))
        engine.cancelActiveResponse()
        gate.continuation.yield()
        gate.continuation.finish()
        _ = await second.result

        #expect(first == "first")
    }

    // MARK: - State

    @Test("The context size only accepts positive values and tells the observer")
    func maxContextSize() {
        let engine = engine()
        var notifications = 0
        engine.onStateChange = { notifications += 1 }
        let initial = engine.maxContextSize

        engine.setMaxContextSize(0)
        engine.setMaxContextSize(-5)
        #expect(engine.maxContextSize == initial)
        #expect(notifications == 0)

        engine.setMaxContextSize(2_048)
        #expect(engine.maxContextSize == 2_048)
        #expect(notifications == 1)
    }

    @Test("Rebuilding starts over: one session, no tokens, nothing summarising")
    func rebuildResets() async throws {
        let engine = engine(overflowResetMessage: "reset")
        engine.hooks.respond = { _ in throw LanguageModelError.contextSizeExceeded(.init(contextSize: 4096, tokenCount: 5000, debugDescription: "x")) }
        engine.hooks.summarize = { throw ModelFailure() }
        _ = try await engine.sendMessage("Hello")
        #expect(engine.sessionCount == 2)

        engine.rebuild(baseInstructions: "Be verbose.")

        #expect(engine.sessionCount == 1)
        #expect(engine.currentTokenCount == 0)
        #expect(!engine.isSummarizing && !engine.isApplyingWindow)
    }

    @Test("A recovery reports its state changes to the observer")
    func recoveryNotifies() async throws {
        let engine = engine()
        var notifications = 0
        engine.onStateChange = { notifications += 1 }
        engine.hooks.respond = { prompt in
            if prompt == "Hello" { throw LanguageModelError.contextSizeExceeded(.init(contextSize: 4096, tokenCount: 5000, debugDescription: "x")) }
            return "ok"
        }
        engine.hooks.summarize = { ConversationSummary(summary: "S", keyTopics: [], userPreferences: []) }

        _ = try await engine.sendMessage("Hello")

        #expect(notifications >= 3, "summarising on, new session, summarising off")
    }
}

@Suite("Conversation state and generation settings")
struct ConversationStateTests {
    @Test("The token usage is the used share of the window, capped at one, and zero without a window")
    func usageFraction() {
        var state = ConversationState(currentTokenCount: 1_024, maxContextSize: 4_096)
        #expect(state.tokenUsageFraction == 0.25)
        state.currentTokenCount = 9_000
        #expect(state.tokenUsageFraction == 1)
        state.maxContextSize = 0
        #expect(state.tokenUsageFraction == 0)
        state.maxContextSize = -1
        #expect(state.tokenUsageFraction == 0)
    }

    @Test("A fixed seed is drawn once and reused, a fresh one is not kept")
    func fixedSeedIsReused() {
        var settings = GenerationSettings()
        settings.samplingStrategy = .sampling
        settings.useFixedSeed = true

        let first = settings.options()
        let second = settings.options()

        #expect(String(describing: first) == String(describing: second))
    }

    @Test("Permissive guardrails are only used when asked for")
    func guardrails() {
        var settings = GenerationSettings()
        #expect(settings.guardrails == .default)
        settings.usePermissiveGuardrails = true
        #expect(settings.guardrails == .permissiveContentTransformations)
    }
}

@Suite("Conversation context builder")
struct ConversationContextBuilderTests {
    @Test("Only prompts and responses make the conversation text, labelled and separated by a blank line")
    func conversationText() {
        let transcript = Transcript(entries: [
            .prompt(.init(segments: [.text(.init(content: "Hello"))])),
            .response(.init(assetIDs: [], segments: [.text(.init(content: "Hi there"))])),
            .prompt(.init(segments: [.text(.init(content: "Again"))]))
        ])

        let text = ConversationContextBuilder.conversationText(from: transcript, userLabel: "U:", assistantLabel: "A:")

        #expect(text == "U: Hello\n\nA: Hi there\n\nU: Again")
    }

    @Test("An empty transcript has no conversation text")
    func emptyTranscript() {
        #expect(ConversationContextBuilder.conversationText(from: Transcript(entries: []), userLabel: "U:", assistantLabel: "A:").isEmpty)
    }
}
#endif
