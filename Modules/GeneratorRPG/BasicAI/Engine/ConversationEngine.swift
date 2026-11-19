// @copyright André Trettin

import Foundation
import FoundationModels

@MainActor
public final class ConversationEngine {
    public var onStateChange: (@MainActor () -> Void)?

    public private(set) var session: LanguageModelSession
    public private(set) var sessionCount: Int = 1
    public private(set) var currentTokenCount: Int = 0
    public private(set) var maxContextSize: Int
    public private(set) var isSummarizing: Bool = false
    public private(set) var isApplyingWindow: Bool = false

    /// The three calls that need the on-device model. A test replaces them to drive the overflow
    /// recovery, the streaming task and the session reset without Apple Intelligence; the
    /// production engine leaves them `nil`. See CODE_AUDIT_TestGaps §5.8.
    struct ModelHooks {
        var respond: (@MainActor (_ prompt: String) async throws -> String)?
        var streamedContent: (@MainActor (_ prompt: String) -> AsyncThrowingStream<String, any Error>)?
        var summarize: (@MainActor () async throws -> ConversationSummary)?
    }

    var hooks = ModelHooks()

    private var configuration: ConversationConfiguration
    private var model: SystemLanguageModel
    private var activeStreamingTask: Task<String, Error>?
    private var activeStreamingTaskId: UUID?

    init(configuration: ConversationConfiguration) {
        self.configuration = configuration
        self.model = SystemLanguageModel(
            useCase: configuration.modelUseCase.foundationModelsValue,
            guardrails: configuration.guardrails.foundationModelsValue
        )
        self.maxContextSize = configuration.defaultMaxContextSize
        self.session = Self.makeSession(
            model: model,
            tools: configuration.tools,
            instructions: configuration.baseInstructions
        )
    }

    public func setMaxContextSize(_ value: Int) {
        guard value > 0 else { return }
        maxContextSize = value
        notifyStateChange()
    }

    func rebuild(
        baseInstructions: String? = nil,
        guardrails: GuardrailsConfiguration? = nil
    ) {
        if let baseInstructions {
            configuration.baseInstructions = baseInstructions
        }
        if let guardrails {
            configuration.guardrails = guardrails
        }

        model = SystemLanguageModel(
            useCase: configuration.modelUseCase.foundationModelsValue,
            guardrails: configuration.guardrails.foundationModelsValue
        )
        resetSession()
    }

    public func cancelActiveResponse() {
        activeStreamingTask?.cancel()
        activeStreamingTask = nil
        activeStreamingTaskId = nil
    }

    public func prewarm(promptPrefix: Prompt? = nil) {
        if let promptPrefix {
            session.prewarm(promptPrefix: promptPrefix)
        } else {
            session.prewarm()
        }
    }

    func sendStreamingMessage(
        _ content: String,
        generationOptions: GenerationOptionsConfiguration? = nil,
        onPartialResponse: (@MainActor @Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let prompt = try validatedPrompt(from: content)

        do {
            if await shouldApplyWindow() {
                await applySlidingWindow()
            }

            let response = try await streamResponse(
                to: prompt,
                generationOptions: generationOptions,
                onPartialResponse: onPartialResponse
            )
            await updateTokenCount()
            return response
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            return try await recoverFromContextOverflow(
                userMessage: prompt,
                generationOptions: generationOptions,
                responseMode: .streaming,
                onPartialResponse: onPartialResponse
            )
        }
    }

    func sendMessage(
        _ content: String,
        generationOptions: GenerationOptionsConfiguration? = nil
    ) async throws -> String {
        let prompt = try validatedPrompt(from: content)

        do {
            if await shouldApplyWindow() {
                await applySlidingWindow()
            }

            let response = try await respond(to: prompt, generationOptions: generationOptions)
            await updateTokenCount()
            return response
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            return try await recoverFromContextOverflow(
                userMessage: prompt,
                generationOptions: generationOptions,
                responseMode: .oneShot,
                onPartialResponse: nil
            )
        }
    }
}

private extension ConversationEngine {
    enum ResponseMode {
        case streaming
        case oneShot
    }

    func validatedPrompt(from content: String) throws -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FoundationModelCoreError.invalidRequest(
                String(localized: "Missing prompt", bundle: .module)
            )
        }
        return trimmed
    }

    func resetSession() {
        cancelActiveResponse()
        sessionCount = 1
        currentTokenCount = 0
        isSummarizing = false
        isApplyingWindow = false
        session = Self.makeSession(
            model: model,
            tools: configuration.tools,
            instructions: configuration.baseInstructions
        )
        notifyStateChange()
    }

    func shouldApplyWindow() async -> Bool {
        guard configuration.enableSlidingWindow, configuration.tools.isEmpty else {
            return false
        }

        return await session.transcript.foundationLabIsApproachingLimit(
            threshold: configuration.windowThreshold,
            maxTokens: maxContextSize,
            using: model
        )
    }

    func applySlidingWindow() async {
        guard configuration.enableSlidingWindow, configuration.tools.isEmpty else {
            return
        }

        isApplyingWindow = true
        notifyStateChange()

        let windowEntries = await session.transcript.foundationLabEntriesWithinTokenBudget(
            configuration.targetWindowSize,
            using: model
        )
        let transcript = Transcript(entries: windowEntries)

        session = LanguageModelSession(model: model, transcript: transcript)
        sessionCount += 1
        await updateTokenCount()

        isApplyingWindow = false
        notifyStateChange()
    }

    func updateTokenCount() async {
        currentTokenCount = await session.transcript.foundationLabTokenCount(using: model)
        notifyStateChange()
    }

    func streamResponse(
        to prompt: String,
        generationOptions: GenerationOptionsConfiguration?,
        onPartialResponse: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> String {
        activeStreamingTask?.cancel()
        let task = Task<String, Error>(name: "Foundation Response Stream") { @MainActor [weak self] in
            guard let self else {
                throw CancellationError()
            }

            var latest = ""
            if let streamedContent = self.hooks.streamedContent {
                for try await content in streamedContent(prompt) {
                    latest = content
                    onPartialResponse?(content)
                }
            } else if let generationOptions {
                for try await snapshot in self.session.streamResponse(
                    to: Prompt(prompt),
                    options: generationOptions.foundationModelsValue
                ) {
                    latest = snapshot.content
                    onPartialResponse?(snapshot.content)
                }
            } else {
                for try await snapshot in self.session.streamResponse(to: Prompt(prompt)) {
                    latest = snapshot.content
                    onPartialResponse?(snapshot.content)
                }
            }
            return latest.isEmpty ? self.latestResponseText() : latest
        }

        let taskId = UUID()
        activeStreamingTask = task
        activeStreamingTaskId = taskId
        defer {
            // Only clear the handle if a newer call has not already replaced it,
            // so a superseded call's cleanup cannot drop the current task's handle.
            // See CODE_AUDIT_17 §3.4.
            if activeStreamingTaskId == taskId {
                activeStreamingTask = nil
                activeStreamingTaskId = nil
            }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func respond(
        to prompt: String,
        generationOptions: GenerationOptionsConfiguration?
    ) async throws -> String {
        if let respond = hooks.respond {
            return try await respond(prompt)
        }
        if let generationOptions {
            return try await session.respond(
                to: Prompt(prompt),
                options: generationOptions.foundationModelsValue
            ).content
        }

        return try await session.respond(to: Prompt(prompt)).content
    }

    func recoverFromContextOverflow(
        userMessage: String,
        generationOptions: GenerationOptionsConfiguration?,
        responseMode: ResponseMode,
        onPartialResponse: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> String {
        isSummarizing = true
        notifyStateChange()

        defer {
            isSummarizing = false
            notifyStateChange()
        }

        let promptWithContext: String
        do {
            let summary = try await generateConversationSummary()
            promptWithContext = createNewSession(with: summary, userMessage: userMessage)
        } catch {
            // A cancelled caller must not reset the shared session another call may be using.
            // See CODE_AUDIT_26 §3.13.
            if error is CancellationError || Task.isCancelled {
                throw error
            }
            createFreshSessionAfterOverflow()

            if let overflowResetMessage = trimmedOverflowResetMessage() {
                onPartialResponse?(overflowResetMessage)
                return overflowResetMessage
            }

            throw error
        }

        let response: String
        switch responseMode {
        case .streaming:
            response = try await streamResponse(
                to: promptWithContext,
                generationOptions: generationOptions,
                onPartialResponse: onPartialResponse
            )
        case .oneShot:
            response = try await respond(to: promptWithContext, generationOptions: generationOptions)
        }

        await updateTokenCount()
        return response
    }

    /// How much of the conversation is summarised after an overflow: about half of the on-device
    /// model's 4,096-token window, which leaves room for the instructions and the summary.
    static let maximumSummaryInputCharacters = 6_000

    func generateConversationSummary() async throws -> ConversationSummary {
        if let summarize = hooks.summarize {
            return try await summarize()
        }
        let summarySession = LanguageModelSession(
            model: model,
            instructions: Instructions(configuration.summaryInstructions)
        )

        // The newest part only. This runs because the transcript overflowed the context window;
        // sent whole to the summary session it overflowed that one as well, and the
        // conversation was then dropped instead of summarised. See CODE_AUDIT_21 §5.28.
        let conversationText = String(ConversationContextBuilder.conversationText(
            from: session.transcript,
            userLabel: configuration.conversationUserLabel,
            assistantLabel: configuration.conversationAssistantLabel
        ).suffix(Self.maximumSummaryInputCharacters))
        let summaryPrompt = """
        \(configuration.summaryPromptPreamble)

        \(conversationText)
        """

        let summaryResponse = try await summarySession.respond(
            to: Prompt(summaryPrompt),
            generating: ConversationSummary.self
        )

        return summaryResponse.content
    }

    /// Recreates the session with only the static, developer-authored base instructions —
    /// never the model-generated `summary` (see `ConversationContextBuilder.contextPrompt`'s
    /// doc comment) — and returns the continuation prompt to send as this session's first
    /// `prompt:`, carrying `summary` and `userMessage` instead.
    func createNewSession(with summary: ConversationSummary, userMessage: String) -> String {
        session = Self.makeSession(
            model: model,
            tools: configuration.tools,
            instructions: configuration.baseInstructions
        )
        sessionCount += 1
        currentTokenCount = 0
        notifyStateChange()

        return ConversationContextBuilder.contextPrompt(
            summary: summary,
            continuationNote: configuration.continuationNote,
            userMessage: userMessage
        )
    }

    func createFreshSessionAfterOverflow() {
        session = Self.makeSession(
            model: model,
            tools: configuration.tools,
            instructions: configuration.baseInstructions
        )
        sessionCount += 1
        currentTokenCount = 0
        notifyStateChange()
    }

    func trimmedOverflowResetMessage() -> String? {
        guard let message = configuration.overflowResetMessage?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return nil
        }

        return message
    }

    func latestResponseText() -> String {
        for entry in session.transcript.reversed() {
            switch entry {
            case .response:
                return entry.textContent() ?? ""
            case .prompt:
                return ""
            default:
                continue
            }
        }
        return ""
    }

    static func makeSession(
        model: SystemLanguageModel,
        tools: [any Tool],
        instructions: String
    ) -> LanguageModelSession {
        let trimmedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tools.isEmpty {
            if trimmedInstructions.isEmpty {
                return LanguageModelSession(model: model, tools: tools)
            }
            return LanguageModelSession(
                model: model,
                tools: tools,
                instructions: Instructions(trimmedInstructions)
            )
        }

        if trimmedInstructions.isEmpty {
            return LanguageModelSession(model: model)
        }

        return LanguageModelSession(
            model: model,
            instructions: Instructions(trimmedInstructions)
        )
    }

    func notifyStateChange() {
        onStateChange?()
    }
}
