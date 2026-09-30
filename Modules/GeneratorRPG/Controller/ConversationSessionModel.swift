// @copyright André Trettin

#if !os(tvOS)

import Foundation
import FoundationModels

/// Sampling and guardrail options for a generator conversation.
struct GenerationSettings {
    var samplingStrategy: SamplingStrategyConfiguration = .default
    var useFixedSeed = false
    var usePermissiveGuardrails = false
    var topKSamplingValue = 50
    private var samplingSeed: UInt64?

    /// The options for the next request. A fixed seed is drawn once and then reused.
    mutating func options() -> GenerationOptionsConfiguration {
        switch samplingStrategy {
        case .default:
            return GenerationOptionsConfiguration()
        case .greedy:
            return GenerationOptionsConfiguration(sampling: .greedy)
        case .sampling:
            let seed: UInt64? = useFixedSeed ? (samplingSeed ?? storeNewSeed()) : nil
            return GenerationOptionsConfiguration(
                sampling: .randomTop(topKSamplingValue, seed: seed)
            )
        }
    }

    var guardrails: GuardrailsConfiguration {
        usePermissiveGuardrails ? .permissiveContentTransformations : .default
    }

    private mutating func storeNewSeed() -> UInt64 {
        let seed = UInt64.random(in: UInt64.min...UInt64.max)
        samplingSeed = seed
        return seed
    }
}

/// Token and summarising state mirrored from a `ConversationEngine`.
struct ConversationState {
    var currentTokenCount = 0
    var maxContextSize = AppConfiguration.TokenManagement.defaultMaxTokens
    var isSummarizing = false
    var isApplyingWindow = false
    var sessionCount = 1

    var tokenUsageFraction: Double {
        guard maxContextSize > 0 else { return 0 }
        return min(1.0, Double(currentTokenCount) / Double(maxContextSize))
    }
}

/// A generator session model that drives one `ConversationEngine`. The generation options,
/// the token bookkeeping and the engine wiring were copied between `GeneratorSessionModel`
/// and `AdventureSessionModel`; fixes already had to be made twice (CODE_AUDIT_18 §5.20).
/// See CODE_AUDIT_19 §9.16.
@MainActor
protocol ConversationSessionModel: AnyObject {
    var conversationEngine: ConversationEngine { get }
    var session: LanguageModelSession { get set }
    var generationSettings: GenerationSettings { get set }
    var conversationState: ConversationState { get set }
}

extension ConversationSessionModel {
    /// Call once from `init`: mirrors every engine state change and loads the context size.
    func observeConversationEngine() {
        conversationEngine.onStateChange = { [weak self] in
            self?.syncConversationState()
        }
        Task(name: "Foundation Context Size") { [weak self] in
            await self?.fetchContextSize()
        }
    }

    func syncConversationState() {
        session = conversationEngine.session
        conversationState.currentTokenCount = conversationEngine.currentTokenCount
        conversationState.maxContextSize = conversationEngine.maxContextSize
        conversationState.isSummarizing = conversationEngine.isSummarizing
        conversationState.isApplyingWindow = conversationEngine.isApplyingWindow
        conversationState.sessionCount = conversationEngine.sessionCount
    }

    func fetchContextSize() async {
        let contextSize = await AppConfiguration.TokenManagement.contextSize(
            modelUseCase: .general,
            guardrails: generationSettings.guardrails
        )
        conversationEngine.setMaxContextSize(contextSize)
        syncConversationState()
    }
}

#endif
