// @copyright André Trettin

import Foundation
import FoundationModels
import Observation
import Speech

@MainActor
@Observable
final class ChatViewModel {

    // MARK: - Published Properties

    var isLoading: Bool = false

    private let conversationEngine: ConversationEngine
    var isSummarizing: Bool = false
    var isApplyingWindow: Bool = false
    var sessionCount: Int = 1
    var instructions: String
    var SamplingStrategyConfiguration: SamplingStrategyConfiguration = .default
    var topKSamplingValue: Int = 50
    var useFixedSeed: Bool = false
    var usePermissiveGuardrails: Bool = false
    private var samplingSeed: UInt64?
    var errorMessage: String?
    var showError: Bool = false

    // MARK: - Token Usage Tracking

    private(set) var currentTokenCount: Int = 0
    private(set) var maxContextSize: Int = AppConfiguration.TokenManagement.defaultMaxTokens

    var tokenUsageFraction: Double {
        guard maxContextSize > 0 else { return 0 }
        return min(1.0, Double(currentTokenCount) / Double(maxContextSize))
    }

    // MARK: - Public Properties

    private(set) var session: LanguageModelSession

    // MARK: - Feedback State

    private(set) var feedbackState: [Transcript.Entry.ID: LanguageModelFeedback.Sentiment] = [:]

    // MARK: - Generation Options

    var generationOptions: GenerationOptionsConfiguration {
        switch SamplingStrategyConfiguration {
        case .default:
            return GenerationOptionsConfiguration()
        case .greedy:
            return GenerationOptionsConfiguration(sampling: .greedy)
        case .sampling:
            let seed: UInt64? = useFixedSeed ? (samplingSeed ?? generateAndStoreSeed()) : nil
            return GenerationOptionsConfiguration(
                sampling: .randomTop(topKSamplingValue, seed: seed)
            )
        }
    }

    // MARK: - Initialization

    init() {
        self.instructions = Self.defaultInstructions

        let configuration = ConversationConfiguration(
            baseInstructions: Self.defaultInstructions,
            summaryInstructions: """
            You are an expert at summarizing conversations. Create comprehensive summaries that \
            preserve all important context and details.
            """,
            summaryPromptPreamble: """
            Please summarize the following entire conversation comprehensively. Include all key points, \
            topics discussed, user preferences, and important context that would help continue the \
            conversation naturally:
            """,
            conversationUserLabel: "User:",
            conversationAssistantLabel: "Assistant:",
            continuationNote: """
            Continue the conversation naturally, referencing this context when relevant. \
            The user's next message is a continuation of your previous discussion.
            """,
            modelUseCase: .general,
            guardrails: .default,
            enableSlidingWindow: true,
            windowThreshold: AppConfiguration.TokenManagement.windowThreshold,
            targetWindowSize: AppConfiguration.TokenManagement.targetWindowSize,
            defaultMaxContextSize: AppConfiguration.TokenManagement.defaultMaxTokens
        )
        let engine = ConversationEngine(configuration: configuration)
        self.conversationEngine = engine
        self.session = engine.session

        engine.onStateChange = { [weak self] in
            self?.syncConversationState()
        }
        syncConversationState()

        Task {
            await fetchContextSize()
        }
    }

    // MARK: - Public Methods

    func sendMessage(_ content: String) async {
        isLoading = true
        defer { isLoading = session.isResponding }

        do {
            _ = try await conversationEngine.sendStreamingMessage(
                content,
                generationOptions: generationOptions
            )
            syncConversationState()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = FoundationModelsErrorHandler.handleError(error)
            showError = true
        }
    }

    func submitFeedback(for entryID: Transcript.Entry.ID, sentiment: LanguageModelFeedback.Sentiment) {
        feedbackState[entryID] = sentiment
        _ = session.logFeedbackAttachment(sentiment: sentiment)
    }

    func getFeedback(for entryID: Transcript.Entry.ID) -> LanguageModelFeedback.Sentiment? {
        feedbackState[entryID]
    }

    func clearChat() {
        conversationEngine.clear()
        feedbackState.removeAll()
        isLoading = false
        errorMessage = nil
        showError = false
        syncConversationState()
    }

    func updateInstructions(_ newInstructions: String) {
        instructions = newInstructions
        conversationEngine.rebuild(
            baseInstructions: newInstructions,
            guardrails: currentGuardrails()
        )
        syncConversationState()
    }

    func dismissError() {
        showError = false
        errorMessage = nil
    }

    func tearDown() {
        conversationEngine.cancelActiveResponse()
    }
}

private extension ChatViewModel {
    static let defaultInstructions = """
    You are a helpful, friendly AI assistant. Engage in natural conversation and provide
    thoughtful, detailed responses.
    """

    func syncConversationState() {
        session = conversationEngine.session
        currentTokenCount = conversationEngine.currentTokenCount
        maxContextSize = conversationEngine.maxContextSize
        isSummarizing = conversationEngine.isSummarizing
        isApplyingWindow = conversationEngine.isApplyingWindow
        sessionCount = conversationEngine.sessionCount
    }

    func fetchContextSize() async {
        let contextSize = await AppConfiguration.TokenManagement.contextSize(
            modelUseCase: .general,
            guardrails: currentGuardrails()
        )
        conversationEngine.setMaxContextSize(contextSize)
        syncConversationState()
    }

    // MARK: - Language Model

    func currentGuardrails() -> GuardrailsConfiguration {
        usePermissiveGuardrails ? .permissiveContentTransformations : .default
    }

    func generateAndStoreSeed() -> UInt64 {
        let seed = UInt64.random(in: UInt64.min...UInt64.max)
        samplingSeed = seed
        return seed
    }
}
