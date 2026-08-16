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
        Task(name: "Foundation Context Size") {
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
    
    // Task management for cancellation
    var currentTask: Task<Void, Never>?
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    // Task management for cancellation extraction
    var currentExtractionTask: Task<Void, Never>?
    func cancelExtraction() {
        currentExtractionTask?.cancel()
        currentExtractionTask = nil
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
    /// True while a stream is actively producing partial results. Callers that need to
    /// persist the final blocks (rather than every partial update) should watch for the
    /// true → false transition.
    var isExtracting: Bool = false
    func set(extractSession: LanguageModelSession) {
        self.extractSession = extractSession
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

    @MainActor var availblity: Bool {
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

    @MainActor func preparaEngine(module: NetworkModules) async {
        model.conversationEngine.prewarm()
        
        let extractInstructions = """
        Extract the response into individual sheet entries for module type \(module.title).
        Split every numbered item, bullet point, or distinct topic into its own entry.
        Never combine multiple items into a single entry.
        Each entry needs a concise title and its full content.
        Preserve the language of the source text.
        """

        let session = LanguageModelSession(instructions: extractInstructions)
        self.model.set(extractSession: session)
        session.prewarm()
    }
            
    @MainActor func request(message: String, rootModel: SheetRootModel) {
        model.cancel()
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
            defer { model.isLoading = model.session.isResponding }
            do {
                let typeId = rootSheetModel.source.typeId
                let response = try await model.conversationEngine.sendStreamingMessage(
                    prompt,
                    generationOptions: model.generationOptions
                ) { @MainActor partialText in
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
                model.syncConversationState()
                model.responseErrorContent = ""
                model.chatResponse = response
                extract(message: response, rootModel: rootModel)
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
        //model.feedbackState.removeAll()
        model.isLoading = false
        model.responseErrorContent = ""
        model.showError = false
        model.syncConversationState()
    }

    // MARK: - Extraction

    @MainActor func extract(message: String, rootModel: SheetRootModel) {
        model.cancelExtraction()
        model.isExtracting = true
        let typeId = rootModel.sheetModel.source.typeId
        PerformanceTrace.event("FoundationRequest", source: "extraction", count: message.count)

        model.currentExtractionTask = Task(name: "Foundation Extraction") {
            let trace = PerformanceTrace.begin(
                "FoundationExtraction",
                source: "extraction",
                count: message.count
            )
            defer { trace?.end() }
            defer { model.isExtracting = model.extractSession.isResponding }
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

                let finalEntries = self.model.blockResponse.compactMap { partial -> SheetModel? in
                    guard let name = partial.title, let content = partial.content else { return nil }
                    return makeSheetEntry(name: name, content: content, typeId: typeId)
                }
                withAnimation(.smooth) { rootModel.updateAIGenerated(finalEntries) }
                withAnimation(.smooth) { rootModel.updateAIPreview(nil) }

            } catch let error as LanguageModelSession.GenerationError {
                withAnimation(.smooth) { rootModel.updateAIPreview(nil) }
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
    
    @MainActor func drafts(from block: BlockGenModel) -> SheetModel? {
        let entryDrafts = block.entries.compactMap { entry -> SheetModel? in
            let title = cleaned(entry.title)
            let content = cleaned(entry.content)
            guard !title.isEmpty || !content.isEmpty else { return nil }
            let sheetModel = SheetModel(source: ItemRowModel(itemId: UUID(), typeId: .adventure), name: title, description: content, entries: [])
            sheetModel.isGeneratedAnswer = true
            return sheetModel
        }
        
        let title = cleaned(block.name)
        let content = cleaned(block.information)
        guard !title.isEmpty || !content.isEmpty else { return nil }
        
        let sheetModel = SheetModel(source: ItemRowModel(itemId: UUID(), typeId: .adventure), name: title, description: content, entries: entryDrafts)
        sheetModel.isGeneratedAnswer = true
        return sheetModel
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


/*
public private(set) var pendingGenerationRequest: SheetGenerationRequest?
public private(set) var generatedBatch: SheetGeneratedBatch?
private var pendingGenerationParentModel: SheetModel?
private var generatedBatchParentModel: SheetModel?
private var generatedAcceptanceTransitions: [GeneratedAcceptanceKey: UUID] = [:]

 /// Whether the sheet contains non-root content that can give the assistant useful context.
 /// The root item's title alone does not make an otherwise empty sheet eligible.
 public var hasAIAssistantContent: Bool {
     (sheetModel.entries + sheetModel.inlineEntries).contains(where: containsGenerationContent)
 }

 private func containsGenerationContent(_ model: SheetModel) -> Bool {
     model.hasGenerationContent ||
     (model.entries + model.inlineEntries).contains(where: containsGenerationContent)
 }

 // MARK: Generation Queue

 @discardableResult
 public func queueGeneration(prompt: String, module defaultModule: NetworkModules) -> SheetGenerationRequest? {
     let parent = selectedParentModel ?? sheetModel
     return queueGeneration(
         prompt: prompt,
         focusedEntry: selectedEntry,
         parent: parent,
         defaultModule: defaultModule
     )
 }

 @discardableResult
 public func queueGeneration(
     from entryModel: SheetModel,
     parent parentModel: SheetModel,
     module defaultModule: NetworkModules
 ) -> SheetGenerationRequest? {
     guard entryModel.hasGenerationContent else { return nil }
     setSelected(entryModel, parent: parentModel)
     return queueGeneration(
         prompt: "",
         focusedEntry: entryModel,
         parent: parentModel,
         defaultModule: defaultModule
     )
 }

 func canRefineGeneratedPreview(_ preview: SheetModel, in parentModel: SheetModel) -> Bool {
     guard preview.isGeneratedAnswer,
           let generatedBatch,
           generatedBatch.entries.contains(where: { $0 === preview }),
           let generatedParent = generatedParent(for: generatedBatch),
           generatedParent === parentModel else {
         return false
     }

     return !preview.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
         !preview.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
 }

 /// Uses one current generated preview as focused AI input. The existing batch stays
 /// visible while generation runs and is replaced atomically only after success.
 @discardableResult
 public func refineGeneratedPreview(
     _ preview: SheetModel,
     in parentModel: SheetModel,
     instruction: String = ""
 ) -> SheetGenerationRequest? {
     guard canRefineGeneratedPreview(preview, in: parentModel),
           let generatedBatch else {
         return nil
     }

     let name = preview.name.trimmingCharacters(in: .whitespacesAndNewlines)
     let content = preview.description.trimmingCharacters(in: .whitespacesAndNewlines)
     let focusedContent = SheetContentSnapshot(
         id: preview.id,
         source: preview.source,
         name: name,
         content: content
     )
     let sheetContext = contentSnapshot(for: parentModel, includeChildren: true) ?? SheetContentSnapshot(
         id: parentModel.id,
         source: parentModel.source,
         name: parentModel.name,
         content: parentModel.description
     )
     let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
     let prompt = trimmedInstruction.isEmpty
         ? "Refine this generated content. Preserve its intent and language while improving clarity and usefulness during play."
         : trimmedInstruction
     let focus = SheetGenerationFocus(
         rootItemID: sheetModel.source.itemId,
         parentModelID: parentModel.id,
         parentSource: parentModel.source,
         selectedModelID: preview.id,
         selectedSource: preview.source,
         position: effectivePosition(for: generatedBatch, in: parentModel),
         module: generatedBatch.focus.module
     )
     let request = SheetGenerationRequest(
         prompt: prompt,
         sheetContext: sheetContext,
         focusedContent: focusedContent,
         focus: focus
     )

     isAIModeActive = true
     pendingGenerationRequest = request
     pendingGenerationParentModel = parentModel
     return request
 }

 /// Removes only a transient preview. No EditController or persisted model is touched.
 @discardableResult
 public func discardGeneratedPreview(_ preview: SheetModel, in parentModel: SheetModel) -> Bool {
     guard preview.isGeneratedAnswer else { return false }

     if var batch = generatedBatch,
        batch.entries.contains(where: { $0 === preview }),
        let generatedParent = generatedParent(for: batch),
        generatedParent === parentModel {
         finishPendingGeneration(focusedOn: preview)
         evictLinkTextModels(for: [preview])
         batch.entries.removeAll { $0 === preview }
         if batch.entries.isEmpty {
             generatedBatch = nil
             generatedBatchParentModel = nil
         } else {
             generatedBatch = batch
             generatedBatchParentModel = generatedParent
         }
         clearScrollTarget(for: preview)
         return true
     }

     // Legacy previews were embedded directly in their parent model.
     guard containsIdentity(parentModel, in: sheetModel),
           parentModel.entries.contains(where: { $0 === preview }) else {
         return false
     }
     finishPendingGeneration(focusedOn: preview)
     evictLinkTextModels(for: [preview])
     parentModel.entries.removeAll { $0 === preview }
     clearScrollTarget(for: preview)
     return true
 }

 public func finishGenerationRequest(_ requestID: UUID) {
     guard pendingGenerationRequest?.id == requestID else { return }
     pendingGenerationRequest = nil
     pendingGenerationParentModel = nil
 }

 public func clearGeneratedPreviews() {
     if let generatedBatch {
         evictLinkTextModels(for: generatedBatch.entries)
     }
     generatedBatch = nil
     generatedBatchParentModel = nil
 }

 @discardableResult
 public func installGeneratedDrafts(_ drafts: [GeneratedSheetDraft], for requestID: UUID) -> Bool {
     guard let request = pendingGenerationRequest,
           request.id == requestID,
           request.focus.rootItemID == sheetModel.source.itemId else {
         return false
     }

     let parent: SheetModel
     if let pendingGenerationParentModel {
         guard pendingGenerationParentModel.id == request.focus.parentModelID,
               containsIdentity(pendingGenerationParentModel, in: sheetModel) else {
             return false
         }
         parent = pendingGenerationParentModel
     } else if let resolvedParent = findEntry(id: request.focus.parentModelID, in: sheetModel) {
         parent = resolvedParent
     } else {
         return false
     }

     let cleanedDrafts = drafts.compactMap { draft -> GeneratedSheetDraft? in
         let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
         let content = draft.content.trimmingCharacters(in: .whitespacesAndNewlines)
         guard !title.isEmpty || !content.isEmpty else { return nil }
         return GeneratedSheetDraft(id: draft.id, title: title, content: content)
     }

     guard !cleanedDrafts.isEmpty else {
         finishGenerationRequest(requestID)
         return false
     }

     let batchID = requestID.uuidString
     let entries = cleanedDrafts.map { draft in
         let source = ItemRowModel(
             itemId: parent.source.itemId,
             entryId: draft.id,
             typeId: request.focus.module
         )
         let entry = SheetModel(
             source: source,
             level: parent.level,
             canAdd: false,
             name: draft.title.isEmpty ? "Generated Entry" : draft.title,
             description: draft.content,
             entries: []
         )
         entry.isGeneratedAnswer = true
         entry.generatedBatchID = batchID
         return entry
     }

     if let generatedBatch {
         evictLinkTextModels(for: generatedBatch.entries)
     }
     generatedBatch = SheetGeneratedBatch(id: batchID, focus: request.focus, entries: entries)
     generatedBatchParentModel = parent
     editorModel.scrollEntryId = entries.last?.source.entryId
     finishGenerationRequest(requestID)
     return true
 }

 // MARK: Preview Acceptance

 func generatedEntries(after entryModel: SheetModel, in parentModel: SheetModel) -> [SheetModel] {
     guard let generatedBatch,
           isParent(parentModel, for: generatedBatch),
           case .after(let entryID) = effectivePosition(for: generatedBatch, in: parentModel),
           entryModel.source.entryId == entryID else {
         return []
     }
     return generatedBatch.entries
 }

 func trailingGeneratedEntries(in parentModel: SheetModel) -> [SheetModel] {
     guard let generatedBatch, isParent(parentModel, for: generatedBatch) else { return [] }

     switch effectivePosition(for: generatedBatch, in: parentModel) {
     case .end:
         return generatedBatch.entries
     case .after(let entryID):
         let anchorStillExists = parentModel.entries.contains { $0.source.entryId == entryID }
         return anchorStillExists ? [] : generatedBatch.entries
     }
 }

 @discardableResult
 public func acceptGeneratedPreview(_ preview: SheetModel) -> UUID? {
     guard var batch = generatedBatch,
           batch.entries.contains(where: { $0 === preview }),
           let parent = generatedParent(for: batch),
           let editable = entryDataEditable(for: parent.source) else {
         return nil
     }

     let insertionPosition = effectivePosition(for: batch, in: parent)
     let previewID = preview.source.entryId ?? preview.source.itemId
     guard let entryID = editable.insertEntry(
         itemId: parent.source.itemId,
         name: preview.name,
         content: preview.description,
         position: insertionPosition
     ) else {
         return nil
     }

     finishPendingGeneration(focusedOn: preview)
     generatedAcceptanceTransitions[
         GeneratedAcceptanceKey(parentModelID: parent.id, persistedEntryID: entryID)
     ] = previewID
     evictLinkTextModels(for: [preview])
     batch.entries.removeAll { $0 === preview }
     batch.lastAcceptedEntryID = entryID
     generatedBatch = batch.entries.isEmpty ? nil : batch
     if batch.entries.isEmpty {
         generatedBatchParentModel = nil
     }

     updateParent(parent)

     let parentStillEmbedded = containsIdentity(parent, in: sheetModel)
     if !batch.entries.isEmpty, parentStillEmbedded {
         generatedBatchParentModel = parent
     } else if !batch.entries.isEmpty {
         evictLinkTextModels(for: batch.entries)
         generatedBatch = nil
         generatedBatchParentModel = nil
     }
     if parentStillEmbedded,
        let acceptedEntry = parent.entries.first(where: { $0.source.entryId == entryID }) {
         setSelected(acceptedEntry, parent: parent)
     }
     editorModel.scrollEntryId = entryID
     MasterRPGTips.recordEntryCreated()
     Task {
         await MasterRPGTips.donateAIAccepted()
     }
     return entryID
 }

 /// Gives an outgoing generated preview and its incoming persisted row one temporary
 /// identity so SwiftUI can animate the handoff even though persistence creates a new UUID.
 func sheetRowGeometryMatch(
     for entryModel: SheetModel,
     parent parentModel: SheetModel
 ) -> SheetRowGeometryMatch {
     if entryModel.isGeneratedAnswer {
         return SheetRowGeometryMatch(
             id: .generated(
                 parent: parentModel.id,
                 draft: entryModel.source.entryId ?? entryModel.source.itemId
             ),
             isSource: true
         )
     }

     if let acceptedEntryID = entryModel.source.entryId,
        let previewID = generatedAcceptanceTransitions[
            GeneratedAcceptanceKey(
                parentModelID: parentModel.id,
                persistedEntryID: acceptedEntryID
            )
        ] {
         return SheetRowGeometryMatch(
             id: .generated(parent: parentModel.id, draft: previewID),
             isSource: false
         )
     }

     return SheetRowGeometryMatch(
         id: .regular(parent: parentModel.id, row: entryModel.id),
         isSource: true
     )
 }

 func finishGeneratedAcceptanceTransition(previewID: UUID, parentModelID: UUID) {
     let matchingKeys = generatedAcceptanceTransitions.compactMap { key, mappedPreviewID in
         key.parentModelID == parentModelID && mappedPreviewID == previewID ? key : nil
     }
     for key in matchingKeys {
         generatedAcceptanceTransitions[key] = nil
     }
 }

 private func queueGeneration(
     prompt: String,
     focusedEntry: SheetModel?,
     parent requestedParent: SheetModel,
     defaultModule: NetworkModules
 ) -> SheetGenerationRequest? {
     let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
     let focusedContent = focusedEntry.flatMap {
         contentSnapshot(for: $0, includeChildren: false)
     }
     guard !trimmedPrompt.isEmpty || focusedContent != nil else { return nil }

     guard let target = generationTarget(
         requestedParent: requestedParent,
         focusedEntry: focusedEntry
     ) else { return nil }

     let sheetContext = contentSnapshot(for: target.parent, includeChildren: true) ?? SheetContentSnapshot(
         id: target.parent.id,
         source: target.parent.source,
         name: target.parent.name,
         content: target.parent.description
     )
     let module = target.parent.source.typeId == .none ? defaultModule : target.parent.source.typeId
     let focus = SheetGenerationFocus(
         rootItemID: sheetModel.source.itemId,
         parentModelID: target.parent.id,
         parentSource: target.parent.source,
         selectedModelID: focusedEntry?.id,
         selectedSource: focusedEntry?.source,
         position: target.position,
         module: module
     )
     let request = SheetGenerationRequest(
         prompt: trimmedPrompt,
         sheetContext: sheetContext,
         focusedContent: focusedContent,
         focus: focus
     )
     isAIModeActive = true
     pendingGenerationRequest = request
     pendingGenerationParentModel = target.parent
     return request
 }

 private struct GenerationTarget {
     let parent: SheetModel
     let position: SheetInsertionPosition
 }

 /// Resolves the requested sheet to a destination that can actually persist entries.
 /// For read-only linked sheets, generation still uses the originally focused row as
 /// input, but persists after the direct containing row in the nearest editable sheet.
 private func generationTarget(
     requestedParent: SheetModel,
     focusedEntry: SheetModel?
 ) -> GenerationTarget? {
     guard let path = identityPath(to: requestedParent, in: sheetModel) else { return nil }

     if requestedParent.source.entryId == nil,
        entryDataEditable(for: requestedParent.source) != nil {
         return GenerationTarget(
             parent: requestedParent,
             position: focusedEntry?.source.entryId.map(SheetInsertionPosition.after) ?? .end
         )
     }

     for index in path.indices.dropLast().reversed() {
         let candidate = path[index]
         guard candidate.source.entryId == nil,
               entryDataEditable(for: candidate.source) != nil else { continue }

         let directChild = path[path.index(after: index)]
         return GenerationTarget(
             parent: candidate,
             position: directChild.source.entryId.map(SheetInsertionPosition.after) ?? .end
         )
     }

     return nil
 }

 private func contentSnapshot(for model: SheetModel, includeChildren: Bool) -> SheetContentSnapshot? {
     guard !model.isGeneratedAnswer else { return nil }

     let children: [SheetContentSnapshot]
     if includeChildren {
         children = (model.entries + model.inlineEntries).compactMap {
             contentSnapshot(for: $0, includeChildren: true)
         }
     } else {
         children = []
     }

     let name = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
     let content = model.description.trimmingCharacters(in: .whitespacesAndNewlines)
     guard !name.isEmpty || !content.isEmpty || !children.isEmpty else { return nil }

     return SheetContentSnapshot(
         id: model.id,
         source: model.source,
         name: name,
         content: content,
         children: children
     )
 }

 // MARK: Entry Commit

 /// Creates real, persisted entries via the module's EditController — not transient
 /// in-memory SheetModels — under `parent` (defaults to the root sheetModel), re-syncs
 /// the tree from the saved data (which drops any unpersisted preview entry with the
 /// same synthetic id — see SheetController.update), and scrolls to the last one.
 @discardableResult
 public func appendEntries(_ blocks: [(title: String, content: String)], into parent: SheetModel? = nil) -> [UUID] {
     let targetParent = parent ?? sheetModel
     guard !blocks.isEmpty, let editable = entryDataEditable(for: targetParent.source) else { return [] }
     let newEntryIds = blocks.map { block in
         let entryId = editable.addNewEntry(itemId: targetParent.source.itemId)
         editable.update(itemId: targetParent.source.itemId, entryId: entryId, name: block.title, content: block.content)
         return entryId
     }
     updateParent(targetParent)
     if let lastEntryId = newEntryIds.last {
         editorModel.scrollEntryId = lastEntryId
     }
     return newEntryIds
 }

 /// Commits a temporary, unpersisted `isGeneratedAnswer` preview entry (as created by
 /// SheetAIAssistantOverlayView) into a real, saved entry via the EditController, then
 /// clears the preview flag. Called by the generated entry's Take Over menu action.
 @discardableResult
 public func commitGeneratedEntry(_ entryModel: SheetModel, parent: SheetModel) -> Bool {
     guard entryModel.isGeneratedAnswer else { return false }
     if generatedBatch?.entries.contains(where: { $0 === entryModel }) == true {
         return acceptGeneratedPreview(entryModel) != nil
     }

     // Only previews embedded by the legacy implementation may use this fallback.
     // An external preview from an older/replaced batch is stale and must not persist.
     guard containsIdentity(parent, in: sheetModel),
           parent.entries.contains(where: { $0 === entryModel }),
           let editable = entryDataEditable(for: parent.source),
           let entryID = editable.insertEntry(
             itemId: parent.source.itemId,
             name: entryModel.name,
             content: entryModel.description,
             position: .end
           ) else {
         return false
     }

     let previewID = entryModel.source.entryId ?? entryModel.source.itemId
     finishPendingGeneration(focusedOn: entryModel)
     generatedAcceptanceTransitions[
         GeneratedAcceptanceKey(parentModelID: parent.id, persistedEntryID: entryID)
     ] = previewID
     evictLinkTextModels(for: [entryModel])
     entryModel.isGeneratedAnswer = false
     entryModel.generatedBatchID = nil
     updateParent(parent)
     return true
 }

 private func finishPendingGeneration(focusedOn preview: SheetModel) {
     guard let request = pendingGenerationRequest,
           request.focusedContent?.id == preview.id else {
         return
     }
     finishGenerationRequest(request.id)
 }

 private func clearScrollTarget(for preview: SheetModel) {
     let previewID = preview.source.entryId ?? preview.source.itemId
     if editorModel.scrollEntryId == previewID {
         editorModel.scrollEntryId = nil
     }
 }

 private func generatedParent(for batch: SheetGeneratedBatch) -> SheetModel? {
     if let generatedBatchParentModel {
         guard generatedBatchParentModel.id == batch.focus.parentModelID,
               containsIdentity(generatedBatchParentModel, in: sheetModel) else {
             return nil
         }
         return generatedBatchParentModel
     }
     return findEntry(id: batch.focus.parentModelID, in: sheetModel)
 }

 private func isParent(_ parent: SheetModel, for batch: SheetGeneratedBatch) -> Bool {
     guard batch.focus.parentModelID == parent.id else { return false }
     if let generatedBatchParentModel {
         guard containsIdentity(generatedBatchParentModel, in: sheetModel) else { return false }
         return generatedBatchParentModel === parent
     }
     return true
 }

 private func effectivePosition(
     for batch: SheetGeneratedBatch,
     in parent: SheetModel
 ) -> SheetInsertionPosition {
     if let lastAcceptedEntryID = batch.lastAcceptedEntryID,
        parent.entries.contains(where: { $0.source.entryId == lastAcceptedEntryID }) {
         return .after(lastAcceptedEntryID)
     }
     return batch.focus.position
 }

 private func evictLinkTextModels(for models: [SheetModel]) {
     for model in models {
         let lookupID = model.source.entryId ?? model.source.itemId
         linkTextModel[.entry(lookupID)] = nil
         linkTextModel[.entryContent(lookupID)] = nil
         evictLinkTextModels(for: model.inlineEntries)
         evictLinkTextModels(for: model.entries)
     }
 }
 
 */
#endif
