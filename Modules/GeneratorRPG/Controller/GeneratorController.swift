// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import Foundation
import FoundationModels
import SwiftUI

// MARK: - Session Model

@Observable
@MainActor
final class GeneratorSessionModel {
    init(conversationEngine: ConversationEngine) {
        self.conversationEngine = conversationEngine
        self.session = conversationEngine.session
        
        conversationEngine.onStateChange = { [weak self] in
            self?.syncConversationState()
        }
        Task(name: "Foundation Context Size") { [weak self] in
            await self?.fetchContextSize()
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
    
    // Task management for cancellation
    var currentTask: Task<Void, Never>?
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        // Cancelling the wrapper `Task` alone doesn't stop the underlying FoundationModels
        // stream — without this, a superseded/abandoned generation keeps running in the
        // background, burning CPU/battery and still writing into `rootModel` after the UI has
        // moved on. See CODE_AUDIT §5.6.
        conversationEngine.cancelActiveResponse()
    }

    // Task management for cancellation extraction
    var currentExtractionTask: Task<Void, Never>?
    func cancelExtraction() {
        currentExtractionTask?.cancel()
        currentExtractionTask = nil
    }

    /// Monotonically increasing generation counter. `request(message:rootModel:)`
    /// bumps it before starting a new streamed conversation, and `extract(message:rootModel:)`
    /// inherits that same generation for its own stream. Every partial-stream write
    /// compares against this before landing, so a stale generation's late partial
    /// (racing a newer request/extraction) can't overwrite a newer one — cancellation
    /// alone isn't a guarantee the underlying `LanguageModelSession` stream observes
    /// `Task.isCancelled` before its next element. See CODE_AUDIT §3.5.
    private(set) var currentGeneration: Int = 0

    @discardableResult
    func startNewGeneration() -> Int {
        currentGeneration += 1
        return currentGeneration
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
    /// The instructions `extractSession` was last built with — kept so `extract(message:
    /// rootModel:generation:maxCharacters:)` can start each call with a *fresh* session built
    /// from the same instructions, instead of reusing one session (and its growing transcript)
    /// across every extraction. Reusing one session quickly approaches the on-device model's
    /// 4096-token-per-session context window. See CODE_AUDIT_17 §5.20.
    var extractInstructions: String?
    /// True while a stream is actively producing partial results. Callers that need to
    /// persist the final blocks (rather than every partial update) should watch for the
    /// true → false transition.
    var isExtracting: Bool = false
    func set(extractSession: LanguageModelSession, instructions: String) {
        self.extractSession = extractSession
        self.extractInstructions = instructions
    }
    
    // response
    var streamingResponse: String = ""
    var chatResponse: String?
    var blockResponse: [BlockEntryGenModel.PartiallyGenerated] = []
}

// MARK: - Controller

struct GeneratorController: Sendable {
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

        self.model = GeneratorSessionModel(conversationEngine: engine)
        self.foundationManager = FoundationManager()
    }
    
    @MainActor func tearDown() {
        model.conversationEngine.cancelActiveResponse()
        model.currentTask?.cancel()
        // Without this, an in-flight extraction (its own separate session/task from the
        // conversational one above) keeps running and writing into `rootModel` after
        // teardown. See CODE_AUDIT §5.18.
        model.cancelExtraction()
    }

    let model: GeneratorSessionModel
    let foundationManager: FoundationManager

    static let defaultInstructions = """
        You are a creative RPG content generator for a game master.
        Your sole purpose is to CREATE new fictional story elements, scenes, NPCs, items, or events — never to answer questions or summarize existing content.
        Every response must be original, generated fiction ready to use at the table.
        Add hooks to other possible outcomes or story threads.
        Keep responses concise unless the game master asks for detail.
        Preserve the language used by the game master.
    """

    @MainActor var availability: Bool {
        foundationManager.isModelAvailable
    }
    
    // MARK: - Conversation

    /// Resets the session when the focused sheet changes. `sheetIndex` (entry titles, which
    /// can originate from untrusted Foundry VTT import data) is deliberately NOT folded in
    /// here — `instructions:` is the elevated-trust channel. It's attached per-turn to the
    /// `prompt:` in `prompt(for:module:rootSheetModel:focusedContent:)` instead. See CODE_AUDIT §6.3.
    @MainActor func seedConversationContext(sheetModel: SheetModel) {
        let itemId = sheetModel.source.itemId
        guard model.lastItemId != itemId else { return }
        model.lastItemId = itemId
        model.conversationEngine.rebuild(baseInstructions: Self.defaultInstructions)
    }

    @MainActor func prepareEngine(module: NetworkModules) async {
        model.conversationEngine.prewarm()
        
        let extractInstructions = """
        Extract the response into individual sheet entries for module type \(module.title).
        Split every numbered item, bullet point, or distinct topic into its own entry.
        Never combine multiple items into a single entry.
        Each entry needs a concise title and its full content.
        Preserve the language of the source text.
        """

        let session = LanguageModelSession(instructions: extractInstructions)
        self.model.set(extractSession: session, instructions: extractInstructions)
        session.prewarm()
    }
            
    @MainActor func request(message: String, rootModel: SheetRootModel) {
        model.cancel()
        let generation = model.startNewGeneration()
        model.isLoading = true

        let rootSheetModel = rootModel.sheetModel
        let prompt = prompt(for: message, module: rootSheetModel.source.typeId, rootSheetModel: rootSheetModel, focusedContent: nil)

        PerformanceTrace.event("FoundationRequest", source: "conversation", count: message.count)

        let initialPreview = SheetModel(
            source: ItemRowModel(itemId: UUID(), typeId: rootSheetModel.source.typeId),
            name: "",
            description: "",
            entries: []
        )
        initialPreview.isGeneratedAnswer = true
        rootModel.updateAIPreview(initialPreview)

        model.currentTask = Task(name: "Foundation Conversation") {
            let trace = PerformanceTrace.begin(
                "FoundationConversation",
                source: "conversation",
                count: message.count
            )
            defer { trace?.end() }
            // Set deterministically rather than derived from `model.session`, which
            // `ConversationEngine` can reassign mid-flight (e.g. after a sliding-window
            // rebuild) — reading it here risked a spinner stuck `true` after an error, or
            // clearing prematurely while another operation on the swapped-in session was
            // still running. See CODE_AUDIT §5.16.
            // Only the newest request may clear the busy state: a superseded task finishing later
            // used to show an idle UI while the newer request was still generating.
            // See CODE_AUDIT_15 §5.10.
            defer {
                if model.currentGeneration == generation { model.isLoading = false }
            }
            do {
                let typeId = rootSheetModel.source.typeId
                let response = try await model.conversationEngine.sendStreamingMessage(
                    prompt,
                    generationOptions: model.generationOptions
                ) { @MainActor partialText in
                    guard model.currentGeneration == generation else { return }
                    let updated = SheetModel(
                        source: ItemRowModel(itemId: UUID(), typeId: typeId),
                        name: "",
                        description: partialText,
                        entries: []
                    )
                    updated.isGeneratedAnswer = true
                    rootModel.updateAIPreview(updated)
                    model.streamingResponse = partialText
                }
                guard model.currentGeneration == generation else { return }
                model.syncConversationState()
                model.responseErrorContent = ""
                model.chatResponse = response
                extract(message: response, rootModel: rootModel, generation: generation)
            } catch is CancellationError {
                withAnimation(.smooth) { rootModel.updateAIPreview(nil) }
                return
            } catch let error as LanguageModelSession.GenerationError {
                withAnimation(.smooth) { rootModel.updateAIPreview(nil) }
                model.responseErrorContent = FoundationModelsErrorHandler.handleError(error)
                model.showError = true
            } catch {
                withAnimation(.smooth) { rootModel.updateAIPreview(nil) }
                model.responseErrorContent = error.localizedDescription
                model.showError = true
            }
        }
    }
        
    @MainActor func clearChat() {
        model.conversationEngine.clear()
        model.isLoading = false
        model.responseErrorContent = ""
        model.showError = false
        model.syncConversationState()
    }

    // MARK: - Extraction

    @MainActor func extract(message: String, rootModel: SheetRootModel, generation: Int? = nil, maxCharacters: Int = 6_000) {
        model.cancelExtraction()
        // Start this extraction on a fresh session built from the same instructions,
        // rather than continuing to append to `extractSession`'s existing transcript —
        // otherwise every extraction call's prompt/response stayed in the transcript and
        // the on-device model's per-session context window filled after a few calls.
        // See CODE_AUDIT_17 §5.20.
        if let extractInstructions = model.extractInstructions {
            let session = LanguageModelSession(instructions: extractInstructions)
            model.set(extractSession: session, instructions: extractInstructions)
            session.prewarm()
        }
        // Inherit the caller's generation (from `request(message:rootModel:)`) when
        // given, so a newer request supersedes any in-flight extraction from an
        // older one too; a standalone call starts its own generation. See CODE_AUDIT §3.5.
        let generation = generation ?? model.startNewGeneration()
        model.isExtracting = true
        let typeId = rootModel.sheetModel.source.typeId
        // Bounds the text fed into the extraction prompt. Unlike `prompt(for:...)`'s
        // `maxCharacters` cap on the GM's free-text request, the upstream conversational
        // generation itself has no `maximumResponseTokens` limit — an unusually long reply,
        // once wrapped in the extraction instructions and schema, could otherwise exceed the
        // extraction session's own context window on the very next call. See CODE_AUDIT §5.17.
        let message = String(message.prefix(maxCharacters))
        PerformanceTrace.event("FoundationRequest", source: "extraction", count: message.count)

        model.currentExtractionTask = Task(name: "Foundation Extraction") {
            let trace = PerformanceTrace.begin(
                "FoundationExtraction",
                source: "extraction",
                count: message.count
            )
            defer { trace?.end() }
            defer {
                if model.currentGeneration == generation { model.isExtracting = model.extractSession.isResponding }
            }
            var isFirstPartial = true
            var stableCompletedEntries: [SheetModel] = []
            do {
                let prompt = Prompt {
                    "\(message)"
                }
                let stream = model.extractSession.streamResponse(
                    to: prompt,
                    generating: [BlockEntryGenModel].self,
                    includeSchemaInPrompt: true,
                    options: GenerationOptions(maximumResponseTokens: 1200)
                )

                for try await partialResponse in stream {
                    guard model.currentGeneration == generation else { return }
                    let snapshot = partialResponse.content
                    self.model.blockResponse = snapshot
                    guard !snapshot.isEmpty else { continue }

                    if isFirstPartial {
                        isFirstPartial = false
                        withAnimation(.smooth) { rootModel.updateAIPreview(nil) }
                    }

                    let completedSnapshot = snapshot.dropLast()
                    if completedSnapshot.count > stableCompletedEntries.count {
                        let newEntries = completedSnapshot
                            .dropFirst(stableCompletedEntries.count)
                            .compactMap { partial -> SheetModel? in
                                guard let name = partial.title, let content = partial.content else { return nil }
                                return makeSheetEntry(name: name, content: content, typeId: typeId)
                            }
                        if !newEntries.isEmpty {
                            stableCompletedEntries.append(contentsOf: newEntries)
                            withAnimation(.smooth) { rootModel.updateAIGenerated(stableCompletedEntries) }
                        }
                    }

                    if let last = snapshot.last {
                        let preview = SheetModel(
                            source: ItemRowModel(itemId: UUID(), typeId: typeId),
                            name: last.title ?? "",
                            description: last.content ?? "",
                            entries: []
                        )
                        preview.isGeneratedAnswer = true
                        rootModel.updateAIPreview(preview)
                    }
                }

                guard model.currentGeneration == generation else { return }
                let finalEntries = self.model.blockResponse.compactMap { partial -> SheetModel? in
                    guard let name = partial.title, let content = partial.content else { return nil }
                    return makeSheetEntry(name: name, content: content, typeId: typeId)
                }
                withAnimation(.smooth) { rootModel.updateAIGenerated(finalEntries) }
                withAnimation(.smooth) { rootModel.updateAIPreview(nil) }

            } catch let error as LanguageModelSession.GenerationError {
                // Reuse the shared handler `request()`'s catch block already uses, rather
                // than a second, narrower, drifting vocabulary for the same error type. See
                // CODE_AUDIT §5.15.
                withAnimation(.smooth) { rootModel.updateAIPreview(nil) }
                model.responseErrorContent = FoundationModelsErrorHandler.handleError(error)
                if let failureReason = error.failureReason {
                    model.responseErrorContent += "\n\(failureReason)"
                }
                if let recoverySuggestion = error.recoverySuggestion {
                    model.responseErrorContent += "\n\(recoverySuggestion)"
                }
                model.showError = true
            } catch {
                withAnimation(.smooth) { rootModel.updateAIPreview(nil) }
                model.responseErrorContent = error.localizedDescription
                model.showError = true
            }
        }
    }
}

private extension GeneratorController {
    // MARK: Prompt & Sheet Building

    @MainActor func compactSheetIndex(from sheetModel: SheetModel, maxCharacters: Int = 600) -> String {
        var parts: [String] = []
        
        let name = sheetModel.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            parts.append("Sheet: \"\(name)\"")
        }
        
        let entryNames = sheetModel.entries
            .filter { !$0.isGeneratedAnswer }
            .compactMap { entry -> String? in
                let n = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return n.isEmpty ? nil : n
            }
        
        if !entryNames.isEmpty {
            parts.append("Entries: " + entryNames.joined(separator: ", "))
        }
        
        let text = parts.joined(separator: "\n")
        return String(text.prefix(maxCharacters))
    }
    
    @MainActor func makeSheetEntry(name: String, content: String, typeId: NetworkModules) -> SheetModel? {
        let trimmedName = cleaned(name)
        let trimmedContent = cleaned(content)
        guard !trimmedName.isEmpty || !trimmedContent.isEmpty else { return nil }
        let entry = SheetModel(
            source: ItemRowModel(itemId: UUID(), typeId: typeId),
            name: trimmedName,
            description: trimmedContent,
            entries: []
        )
        entry.isGeneratedAnswer = true
        return entry
    }
    
    // focusedContent is reserved for the focused-entry feature (not yet wired).
    @MainActor func prompt(for message: String, module: NetworkModules, rootSheetModel: SheetModel, focusedContent: SheetModel?, maxCharacters: Int = 2_800) -> String {
        // Bound the GM's free-text request itself, not just the sheetIndex
        // context below — `maxCharacters` previously went unused here. See
        // CODE_AUDIT §5.3.
        let trimmed = String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxCharacters))
        let userRequest = trimmed.isEmpty ? "Generate useful new content for this sheet." : trimmed
        var result = "Generate new fictional RPG content for the \(module.title) sheet.\nGame master's request: \(userRequest)"

        // Sheet entry names can originate from untrusted Foundry VTT import data, so this
        // stays in the prompt: rather than being folded into instructions:. See CODE_AUDIT §6.3.
        let sheetIndex = compactSheetIndex(from: rootSheetModel)
        if !sheetIndex.isEmpty {
            result += "\n\nExisting sheet entries (for consistency only — do NOT summarize or answer from these; always generate NEW content):\n\(sheetIndex)"
        }
        return result
    }
    
    func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#endif
