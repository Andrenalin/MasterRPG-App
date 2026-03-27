// @copyright André Trettin

#if !os(tvOS)

import FoundationModels
import Foundation

@Observable
@MainActor
final class AdventureSessionModel {
    init(conversationEngine: FoundationLabConversationEngine) {
        self.conversationEngine = conversationEngine
        self.session = conversationEngine.session
        
        conversationEngine.onStateChange = { [weak self] in
            self?.syncConversationState()
        }
        Task {
            await fetchContextSize()
        }
    }
    
    // session
    let conversationEngine: FoundationLabConversationEngine
    var session: LanguageModelSession

    var isLoading: Bool = false
    var isSummarizing: Bool = false
    var isApplyingWindow: Bool = false
    var sessionCount: Int = 1

    var responseErrorContent: String = ""
    var showError: Bool = false

    func dismissError() {
        showError = false
    }
    
    // chat
    var adventureChat: String?

    // extracting chat
    var extracted: [BlockEntryGenModel.PartiallyGenerated] = []

    // Task management for cancellation
    var currentTask: Task<Void, Never>?

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }
            
    // MARK: - Generation Options
    
    var samplingStrategy: SamplingStrategy = .default
    var useFixedSeed: Bool = false
    var usePermissiveGuardrails: Bool = false
    var topKSamplingValue: Int = 50
    private var samplingSeed: UInt64?
    
    var generationOptions: FoundationLabGenerationOptions {
        switch samplingStrategy {
        case .default:
            return FoundationLabGenerationOptions()
        case .greedy:
            return FoundationLabGenerationOptions(sampling: .greedy)
        case .sampling:
            let seed: UInt64? = useFixedSeed ? (samplingSeed ?? generateAndStoreSeed()) : nil
            return FoundationLabGenerationOptions(
                sampling: .randomTop(topKSamplingValue, seed: seed)
            )
        }
    }
    
    func currentGuardrails() -> FoundationLabGuardrails {
        usePermissiveGuardrails ? .permissiveContentTransformations : .default
    }

    func generateAndStoreSeed() -> UInt64 {
        let seed = UInt64.random(in: UInt64.min...UInt64.max)
        samplingSeed = seed
        return seed
    }

    // token management
    var currentTokenCount: Int = 0
    var maxContextSize: Int = AppConfiguration.TokenManagement.defaultMaxTokens
    
    var tokenUsageFraction: Double {
        guard maxContextSize > 0 else { return 0 }
        return min(1.0, Double(currentTokenCount) / Double(maxContextSize))
    }
    
    @MainActor func syncConversationState() {
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
}

struct AdventureGeneratorController: Sendable {
    @MainActor init() {
        let configuration = FoundationLabConversationConfiguration(
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
        let engine = FoundationLabConversationEngine(configuration: configuration)

        self.model = AdventureSessionModel(conversationEngine: engine)
    }
    
    
    @MainActor func tearDown() {
        model.conversationEngine.cancelActiveResponse()
        model.currentTask?.cancel()
    }

    static let defaultInstructions = """
        You are an assistant to support a game master for creating a fictional game story.
        In the game you have NPC and players characters they have to talk to each other.
        Add connections to other possible outcomes or stories.
        Keep your answer precise except the game master needed a detailed version.
    """

    let model: AdventureSessionModel
    let llm = SystemLanguageModel.default
    
    @MainActor func generate() async {
//        let session = LanguageModelSession {
//        """
//        You are an assistant to support a game master for creating a fictional game story.
//        In the game you have NPC and players characters they have to talk to each other.
//        Add connections to other possible outcomes or stories.
//        Keep your answer precise except the game master needed a detailed version.
//        """
//        }
//        self.model.set(session: session)
        model.session.prewarm()
    }
    
    @MainActor func request(message: String) {
        // Cancel any previous request
        model.cancel()
        model.isLoading = true

        model.currentTask = Task {
            defer { model.isLoading = model.session.isResponding }
            do {
                let prompt = Prompt {
                    "\(message)"
                }
                let stream = model.session.streamResponse(to: prompt, options: GenerationOptions())
                _ = try await model.conversationEngine.sendStreamingMessage(
                    message,
                    generationOptions: model.generationOptions
                )
                model.syncConversationState()
                
                for try await partialResponse in stream {
                    // Check for cancellation
                    try Task.checkCancellation()
                    self.model.adventureChat = partialResponse.content
                }

                // Clear error on success
                model.responseErrorContent = ""
            } catch is CancellationError {
                // Clean cancellation - don't set error
                return
            } catch let error as LanguageModelSession.GenerationError {
                switch error {
                case .guardrailViolation(let context):
                    model.responseErrorContent = "Guardrail Violation: \(context.debugDescription)"
                case .decodingFailure(let context):
                    model.responseErrorContent = "Decoding Failure: \(context.debugDescription)"
                case .rateLimited(let context):
                    model.responseErrorContent = "Rate Limit exceeded: \(context.debugDescription)"
                case .exceededContextWindowSize(let context):
                    model.responseErrorContent = "Memory exceeded: \(context.debugDescription)"
                default:
                    model.responseErrorContent = FoundationModelsErrorHandler.handleError(error)
                    //model.responseErrorContent = "Other error: \(error.localizedDescription)"
                }
                if let failureReason = error.failureReason {
                    model.responseErrorContent += "\n\(failureReason)"
                }
                if let recoverySuggestion = error.recoverySuggestion {
                    model.responseErrorContent += "\n\(recoverySuggestion)"
                }
                model.showError = true
            } catch {
                model.responseErrorContent = error.localizedDescription
                model.showError = true
            }
        }
    }
}

#endif
