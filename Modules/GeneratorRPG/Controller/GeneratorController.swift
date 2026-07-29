// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import Foundation
import FoundationModels

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
    
    // chat
    var adventureChat: String?

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
    var extracted: [BlockEntryGenModel.PartiallyGenerated] = []
    /// True while a stream is actively producing partial results. Callers that need to
    /// persist the final blocks (rather than every partial update) should watch for the
    /// true → false transition.
    var isExtracting: Bool = false
    
    func set(extractSession: LanguageModelSession) {
        self.extractSession = extractSession
    }
}

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
        You are an assistant to support a game master for creating a fictional game story.
        In the game you have NPC and players characters they have to talk to each other.
        Add connections to other possible outcomes or stories.
        Keep your answer precise except the game master needed a detailed version.
        Preserve the language used by the game master.
    """

    @MainActor var availblity: Bool {
        foundationManager.isModelAvailable
    }
    
    @MainActor func preparaEngine(module: NetworkModules) async {
        model.conversationEngine.prewarm()
        
        let introduction = """
        Create structured RPG sheet content for module type \(module.title).
        Return one coherent BlockGenModel. Put each selectable sheet row in its entries array.
        Keep entry titles concise and make entry content immediately useful during play.
        Preserve the language used by the game master.
        """

        let session = LanguageModelSession(instructions: introduction)
        self.model.set(extractSession: session)
        session.prewarm()
    }
    
    @MainActor func generateExtractor() {
        let instructions = """
                Your job is to extyract the text into blocks that can be processed later as text blocks for a bigger story. 
                """
        let session = LanguageModelSession(instructions: instructions)
        
        self.model.set(extractSession: session)
        session.prewarm()
    }


    
    @MainActor func request(message: String, rootSheetModel: SheetModel) {
        // Cancel any previous request
        model.cancel()
        model.isLoading = true
        
        let prompt = prompt(for: message, module: rootSheetModel.source.typeId, rootSheetModel: rootSheetModel, focusedContent: nil)

        PerformanceTrace.event("FoundationRequest", source: "conversation", count: message.count)

        model.currentTask = Task(name: "Foundation Conversation") {
            let trace = PerformanceTrace.begin(
                "FoundationConversation",
                source: "conversation",
                count: message.count
            )
            defer { trace?.end() }
            defer { model.isLoading = model.session.isResponding }
            do {
                let resonpse = try await model.conversationEngine.sendMessage(prompt, generationOptions: model.generationOptions)
                model.syncConversationState()
                // Clear error on success
                model.responseErrorContent = ""
                
                extract(message: resonpse, rootSheetModel: rootSheetModel)
                
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

    @MainActor func extract(message: String, rootSheetModel: SheetModel) {
        model.cancelExtraction()
        model.isExtracting = true
        PerformanceTrace.event("FoundationRequest", source: "extraction", count: message.count)

        model.currentExtractionTask = Task(name: "Foundation Extraction") {
            let trace = PerformanceTrace.begin(
                "FoundationExtraction",
                source: "extraction",
                count: message.count
            )
            defer { trace?.end() }
            defer { model.isExtracting = model.extractSession.isResponding }
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
                
                let sheets = self.model.extracted.compactMap { block -> SheetModel? in
                    guard let name = block.title, let content = block.content else { return nil }
                    return drafts(from: BlockGenModel(name: name, information: content, blockCategory: .adventure, entries: []))
                }
                rootSheetModel.entries.append(contentsOf: sheets)
                
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

private extension GeneratorController {
    @MainActor func drafts(from block: BlockGenModel) -> SheetModel? {
        let entryDrafts = block.entries.compactMap { entry -> SheetModel? in
            let title = cleaned(entry.title)
            let content = cleaned(entry.content)
            guard !title.isEmpty || !content.isEmpty else { return nil }
            var sheetModel = SheetModel(source: ItemRowModel(itemId: UUID(), typeId: .adventure), name: title, description: content, entries: [])
            sheetModel.isGeneratedAnswer = true
            return sheetModel
        }

        let title = cleaned(block.name)
        let content = cleaned(block.information)
        guard !title.isEmpty || !content.isEmpty else { return nil }
        
        var sheetModel = SheetModel(source: ItemRowModel(itemId: UUID(), typeId: .adventure), name: title, description: content, entries: entryDrafts)
        sheetModel.isGeneratedAnswer = true
        return sheetModel
    }

    
    @MainActor func prompt(for message: String, module: NetworkModules, rootSheetModel: SheetModel, focusedContent: SheetModel?, maxCharacters: Int = 2_800) -> String {
        let totalBudget = max(0, maxCharacters)
        guard totalBudget > 0 else { return "" }

        let userPrompt = message.isEmpty
            ? "Generate useful new content from the summary."
            : message
        let introduction = """
        Create structured RPG sheet content for module type \(module.title).
        Return one coherent BlockGenModel. Put each selectable sheet row in its entries array.
        Keep entry titles concise and make entry content immediately useful during play.
        Preserve the language used by the game master.
        """
        let requestHeader = "\n\nGame master's request:\n"
        let focusHeader = "\n\nFocused content:\n"
        let contextHeader = "\n\nContaining sheet context:\n"
        let fixedCharacterCount = introduction.count
            + requestHeader.count
            + focusHeader.count
            + contextHeader.count
        let contentBudget = max(0, totalBudget - fixedCharacterCount)

        let requestedUserBudget = contentBudget / 5
        let requestedFocusBudget = focusedContent == nil
            ? min(80, max(0, contentBudget - requestedUserBudget))
            : contentBudget * 3 / 10
        let requestedContextBudget = max(
            0,
            contentBudget - requestedUserBudget - requestedFocusBudget
        )

        let limitedUserPrompt = limitedCleaned(
            userPrompt,
            maxCharacters: requestedUserBudget
        )
        let unusedUserBudget = max(0, requestedUserBudget - limitedUserPrompt.count)

        let focusedText: String
        if let focusedContent = focusedContent {
            focusedText = render(
                focusedContent,
                maxCharacters: requestedFocusBudget
            )
        } else {
            focusedText = limitedCleaned(
                "None. Add content to the containing sheet.",
                maxCharacters: requestedFocusBudget
            )
        }
        let unusedFocusBudget = max(0, requestedFocusBudget - focusedText.count)

        let contextText = render(
            rootSheetModel,
            maxCharacters: requestedContextBudget + unusedUserBudget + unusedFocusBudget
        )
        let combinedPrompt = introduction
            + requestHeader
            + limitedUserPrompt
            + focusHeader
            + focusedText
            + contextHeader
            + contextText

        return limitedPrefix(combinedPrompt, maxCharacters: totalBudget)
    }
    
    func limitedCleaned(_ value: String, maxCharacters: Int) -> String {
        guard maxCharacters > 0 else { return "" }

        let leadingTrimmed = value.drop(while: { $0.isWhitespace })
        let limited = limitedPrefix(leadingTrimmed, maxCharacters: maxCharacters)
        return limited.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func limitedPrefix<S: StringProtocol>(
        _ value: S,
        maxCharacters: Int
    ) -> String {
        guard maxCharacters > 0 else { return "" }

        let boundedProbe = String(value.prefix(maxCharacters + 1))
        return FoundationModelInputLimiter.limitedText(
            boundedProbe,
            maxCharacters: maxCharacters
        )
    }

    func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    @MainActor func render(
        _ snapshot: SheetModel,
        maxCharacters: Int
    ) -> String {
        guard maxCharacters > 0 else { return "" }

        var builder = SheetAIBoundedStringBuilder(maxCharacters: maxCharacters)
        var stack = [SheetAISnapshotTraversalFrameSheet(snapshot: snapshot, depth: 0)]
        var snapshotsVisited = 0
        let snapshotVisitLimit = max(1, min(256, maxCharacters / 8))

        while !stack.isEmpty,
              builder.remainingCharacters > 0,
              snapshotsVisited < snapshotVisitLimit {
            var frame = stack.removeLast()

            if !frame.didRenderSnapshot {
                snapshotsVisited += 1
                appendSnapshot(frame.snapshot, depth: frame.depth, to: &builder)
                frame.didRenderSnapshot = true
            }

            guard builder.remainingCharacters > 0 else {
                stack.append(frame)
                break
            }

//            if frame.nextChildIndex < frame.snapshot.children.count {
//                let child = frame.snapshot.children[frame.nextChildIndex]
//                frame.nextChildIndex += 1
//                stack.append(frame)
//                stack.append(
//                    SheetAISnapshotTraversalFrameSheet(
//                        snapshot: child,
//                        depth: frame.depth + 1
//                    )
//                )
//            }
        }

        if !stack.isEmpty {
            builder.markTruncated()
        }

        return builder.text
    }

    @MainActor func appendSnapshot(
        _ snapshot: SheetModel,
        depth: Int,
        to builder: inout SheetAIBoundedStringBuilder
    ) {
        let indentation = String(repeating: "  ", count: min(depth, 6))
        appendField(
            snapshot.name,
            prefix: "\(indentation)Title: ",
            maximumValueCharacters: 160,
            to: &builder
        )
        appendField(
            snapshot.description,
            prefix: "\(indentation)Content: ",
            maximumValueCharacters: 420,
            to: &builder
        )
    }

    @MainActor func appendField(
        _ value: String,
        prefix: String,
        maximumValueCharacters: Int,
        to builder: inout SheetAIBoundedStringBuilder
    ) {
        let separatorCharacterCount = builder.text.isEmpty ? 0 : 1
        let availableValueCharacters = max(
            0,
            builder.remainingCharacters - prefix.count - separatorCharacterCount
        )
        let valueBudget = min(maximumValueCharacters, availableValueCharacters)
        let limitedValue = limitedCleaned(value, maxCharacters: valueBudget)
        guard !limitedValue.isEmpty else { return }
        builder.appendLine(prefix + limitedValue)
    }
}


struct SheetAIBoundedStringBuilder {
    init(maxCharacters: Int) {
        self.maxCharacters = max(0, maxCharacters)
    }

    let maxCharacters: Int
    private(set) var text = ""

    var remainingCharacters: Int {
        max(0, maxCharacters - text.count)
    }

    mutating func appendLine(_ line: String) {
        guard remainingCharacters > 0 else { return }

        let value = text.isEmpty ? line : "\n" + line
        let boundedValue = String(value.prefix(remainingCharacters))
        text += boundedValue
    }

    mutating func markTruncated() {
        text = FoundationModelInputLimiter.limitedText(
            text + FoundationModelInputLimiter.truncationMarker,
            maxCharacters: maxCharacters
        )
    }
}

struct SheetAISnapshotTraversalFrameSheet {
    let snapshot: SheetModel
    let depth: Int
    var nextChildIndex = 0
    var didRenderSnapshot = false
}

#endif
