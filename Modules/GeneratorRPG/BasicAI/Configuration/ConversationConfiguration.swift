import Foundation
import FoundationModels

struct ConversationConfiguration {
    public var baseInstructions: String
    public var summaryInstructions: String
    public var summaryPromptPreamble: String
    public var conversationUserLabel: String
    public var conversationAssistantLabel: String
    public var continuationNote: String
    public var overflowResetMessage: String?
    public var modelUseCase: FoundationLabModelUseCase
    public var guardrails: GuardrailsConfiguration
    public var tools: [any Tool]
    public var enableSlidingWindow: Bool
    public var windowThreshold: Double
    public var targetWindowSize: Int
    public var defaultMaxContextSize: Int

    init(
        baseInstructions: String,
        summaryInstructions: String,
        summaryPromptPreamble: String,
        conversationUserLabel: String,
        conversationAssistantLabel: String,
        continuationNote: String,
        overflowResetMessage: String? = nil,
        modelUseCase: FoundationLabModelUseCase = .general,
        guardrails: GuardrailsConfiguration = .default,
        tools: [any Tool] = [],
        enableSlidingWindow: Bool = false,
        windowThreshold: Double = 0.70,
        targetWindowSize: Int = 6_000,
        defaultMaxContextSize: Int = 4_096
    ) {
        self.baseInstructions = baseInstructions
        self.summaryInstructions = summaryInstructions
        self.summaryPromptPreamble = summaryPromptPreamble
        self.conversationUserLabel = conversationUserLabel
        self.conversationAssistantLabel = conversationAssistantLabel
        self.continuationNote = continuationNote
        self.overflowResetMessage = overflowResetMessage
        self.modelUseCase = modelUseCase
        self.guardrails = guardrails
        self.tools = tools
        self.enableSlidingWindow = enableSlidingWindow
        self.windowThreshold = windowThreshold
        self.targetWindowSize = targetWindowSize
        self.defaultMaxContextSize = defaultMaxContextSize
    }
}
