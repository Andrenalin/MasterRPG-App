// @copyright André Trettin

#if !os(tvOS)

import FoundationModels
import Foundation

@Observable
@MainActor
final class AdventureSessionModel {
    init(conversationEngine: ConversationEngine) {
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
    let conversationEngine: ConversationEngine
    var session: LanguageModelSession

    /// The item this session's conversation currently belongs to — used by
    /// GeneratorRootModel.generatorController(for:itemId:) to clear the transcript
    /// when the target item changes within the same module.
    var lastItemId: UUID?

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

    // Task management for cancellation
    var currentTask: Task<Void, Never>?

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }
            
    // MARK: - Generation Options
    
    var SamplingStrategyConfiguration: SamplingStrategyConfiguration = .default
    var useFixedSeed: Bool = false
    var usePermissiveGuardrails: Bool = false
    var topKSamplingValue: Int = 50
    private var samplingSeed: UInt64?
    
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
    
    func currentGuardrails() -> GuardrailsConfiguration {
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
    
    
    // extracting
    var extractSession = LanguageModelSession()
    var extracted: [BlockEntryGenModel.PartiallyGenerated] = []
    /// True while a stream is actively producing partial results. Callers that need to
    /// persist the final blocks (rather than every partial update) should watch for the
    /// true → false transition.
    var isExtracting: Bool = false
    
    func set(extractSession: LanguageModelSession) {
        self.extractSession = extractSession
    }
}

struct AdventureGeneratorController: Sendable {
    @MainActor init() {
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
        model.conversationEngine.prewarm()
    }
    
    @MainActor func request(message: String) {
        // Cancel any previous request
        model.cancel()
        model.isLoading = true

        model.currentTask = Task {
            defer { model.isLoading = model.session.isResponding }
            do {
                _ = try await model.conversationEngine.sendStreamingMessage(
                    message,
                    generationOptions: model.generationOptions
                ) { partial in
                    self.model.adventureChat = partial
                }
                model.syncConversationState()
                
                // Clear error on success
                model.responseErrorContent = ""
            } catch is CancellationError {
                // Clean cancellation - don't set error
                return
            } catch let error as LanguageModelSession.GenerationError {
                model.responseErrorContent = FoundationModelsErrorHandler.handleError(error)
                model.showError = true
            } catch {
                model.responseErrorContent = error.localizedDescription
                model.showError = true
            }
        }
    }
        
    @MainActor func clearChat() {
        model.conversationEngine.clear()
        //model.feedbackState.removeAll()
        model.isLoading = false
        model.responseErrorContent = ""
        model.showError = false
        model.syncConversationState()
    }

    @MainActor func generateExtractor() {
        let instructions = """
                Your job is to extyract the text into blocks that can be processed later as text blocks for a bigger story. 
                """
        let session = LanguageModelSession(instructions: instructions)
        
        self.model.set(extractSession: session)
        session.prewarm()
    }

    @MainActor func extract(message: String) {
        guard !model.extractSession.isResponding else { return }
        model.isExtracting = true

        Task {
            defer { model.isExtracting = false }
            do {
                let prompt = Prompt {
                    "\(message)"
                }
                let stream = model.extractSession.streamResponse(
                    to: prompt,
                    generating: [BlockEntryGenModel].self,
                    includeSchemaInPrompt: false,
                    options: GenerationOptions(maximumResponseTokens: 1200)
                )

                for try await partialResponse in stream {
                    self.model.extracted = partialResponse.content
                }
            } catch let error as LanguageModelSession.GenerationError {
                switch error {
                case .guardrailViolation(let context):
                    model.responseErrorContent = String(
                        localized: "Guardrail Violation: \(context.debugDescription)",
                        bundle: .module
                    )
                case .decodingFailure(let context):
                    model.responseErrorContent = String(
                        localized: "Decoding Failure: \(context.debugDescription)",
                        bundle: .module
                    )
                case .rateLimited(let context):
                    model.responseErrorContent = String(
                        localized: "Rate Limit exceeded: \(context.debugDescription)",
                        bundle: .module
                    )
                case .exceededContextWindowSize(let context):
                    model.responseErrorContent = String(
                        localized: "Memory exceeded: \(context.debugDescription)",
                        bundle: .module
                    )
                default:
                    model.responseErrorContent = String(
                        localized: "Other error: \(error.localizedDescription)",
                        bundle: .module
                    )
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
