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
struct ConversationState: Equatable {
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

/// A generator session model that drives one `ConversationEngine`: the generation options,
/// the token bookkeeping and the engine wiring. `GeneratorSessionModel` is the only conformer
/// since the unused adventure chat copy was removed. See CODE_AUDIT_19 §9.16, CODE_AUDIT_21 §9.1.
@MainActor
protocol ConversationSessionModel: AnyObject {
    var conversationEngine: ConversationEngine { get }
    var session: LanguageModelSession { get set }
    var generationSettings: GenerationSettings { get set }
    var conversationState: ConversationState { get set }

    /// The item this session's conversation currently belongs to — used by
    /// `GeneratorRootModel.generatorController(for:itemId:)` to clear the transcript when the
    /// target item changes within the same module.
    var lastItemId: UUID? { get set }
    var isLoading: Bool { get set }
    var responseErrorContent: String { get set }
    var showError: Bool { get set }
    /// The running generation and extraction, kept so they can be cancelled.
    var currentTask: Task<Void, Never>? { get set }
    var currentExtractionTask: Task<Void, Never>? { get set }
}

extension ConversationSessionModel {
    func dismissError() {
        showError = false
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        // Cancelling the wrapper `Task` alone doesn't stop the underlying FoundationModels
        // stream — without this, a superseded/abandoned generation keeps running in the
        // background, burning CPU/battery and still writing into `rootModel` after the UI has
        // moved on. See CODE_AUDIT §5.6.
        conversationEngine.cancelActiveResponse()
    }

    func cancelExtraction() {
        currentExtractionTask?.cancel()
        currentExtractionTask = nil
    }

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
        // One assignment, and none when nothing changed: five separate writes invalidated the
        // views reading any one of the fields five times per sync. See CODE_AUDIT_20 §7.4.
        let state = ConversationState(
            currentTokenCount: conversationEngine.currentTokenCount,
            maxContextSize: conversationEngine.maxContextSize,
            isSummarizing: conversationEngine.isSummarizing,
            isApplyingWindow: conversationEngine.isApplyingWindow,
            sessionCount: conversationEngine.sessionCount
        )
        if state != conversationState {
            conversationState = state
        }
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
