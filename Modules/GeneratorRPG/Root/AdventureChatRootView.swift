// @copyright André Trettin

import CoreRPG
import FoundationModels
import SwiftUI

struct AdventureChatRootView: View {
    let sheetModel: SheetModel
    var dismissAction: (() -> Void)? = nil

    private let usesAvailabilityGate: Bool
    private let previewBlocks: [AdventureChatBlockSnapshot]?

    @Environment(GeneratorRootModel.self) private var root
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var prompt: String = ""
    @State private var activeAnswerBatchID: String?
    @State private var activeAnswerParentSource: ItemRowModel?
    @State private var activeAnswerParent: SheetModel?
    @State private var didSendInitialContext = false
    @State private var didGenerateSheetBlocks = false
    @State private var didInstallPreviewBlocks = false
    @State private var chatSheetRootModel: SheetRootModel?

    @FocusState private var isTextFieldFocused: Bool

    init(
        sheetModel: SheetModel,
        dismissAction: (() -> Void)? = nil,
        usesAvailabilityGate: Bool = true,
        previewBlocks: [AdventureChatBlockSnapshot]? = nil
    ) {
        self.sheetModel = sheetModel
        self.dismissAction = dismissAction
        self.usesAvailabilityGate = usesAvailabilityGate
        self.previewBlocks = previewBlocks
    }

    private var model: AdventureSessionModel {
        generatorController.model
    }

    private var generatorController: AdventureGeneratorController {
        root.adventureGeneratorController
    }

    var body: some View {
        Group {
            if usesAvailabilityGate {
                FoundationBasicView {
                    contentView
                }
            } else {
                contentView
            }
        }
        .environment(\.colorScheme, colorScheme)
#if os(macOS) || os(visionOS)
        .padding(.top)
#else
        .background(colorScheme == .dark ? Color.black.ignoresSafeArea() : Color.white.ignoresSafeArea())
#endif
#if os(visionOS)
        .glassBackgroundEffect()
#endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark", action: close)
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save", systemImage: "checkmark", action: commitSelection)
                    .disabled(acceptedGeneratedEntries.isEmpty && !sheetModel.hasChanged)
            }
        }
        .navigationTitle(navigationTitle)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

private extension AdventureChatRootView {
    @ViewBuilder var contentView: some View {
        @Bindable var model = model

        Group {
            if let chatSheetRootModel, let sheetRootController {
                ChatSheetRootView(
                    sheetRootController: sheetRootController,
                    sheetRootModel: chatSheetRootModel,
                    sheetModel: sheetModel,
                    model: model,
                    generatorController: generatorController,
                    activeAnswerParentSource: activeAnswerParentSource,
                    prompt: $prompt,
                    isTextFieldFocused: $isTextFieldFocused,
                    prepareForRequestAction: prepareForNewPrompt,
                    requestBlocksAction: requestBlocks,
                    extractAction: extractLatestAnswer,
                    requestSheetDetailAction: requestDetail
                )
            } else {
                ProgressView()
                    .controlSize(.regular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert(
            "Error",
            isPresented: $model.showError,
            actions: { Button { model.dismissError() } label: { Text("OK", bundle: .module) } },
            message: { Text(model.responseErrorContent) }
        )
        .task {
            prepareChatSheetRootModelIfNeeded()
            installPreviewBlocksIfNeeded()
            generatorController.generateExtractor()
            await generatorController.generate()
            try? await Task.sleep(for: .seconds(0.5))
            isTextFieldFocused = true
        }
        .onChange(of: model.extracted.map { "\($0.stableID)-\(String(describing: $0.title))-\(String(describing: $0.content))" }) { _, _ in
            updateActiveAnswerBatch()
        }
        .onDisappear {
            generatorController.tearDown()
        }
    }

    var acceptedGeneratedEntries: [SheetModel] {
        generatedEntries(in: sheetModel).filter(\.isGeneratedAccepted)
    }

    var navigationTitle: String {
        let title = sheetModel.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Adventure" : title
    }

    var sheetModule: NetworkModules {
        sheetModel.source.typeId == .none ? .adventure : sheetModel.source.typeId
    }

    var sheetRootController: ItemRootController? {
        root.rootManager?.itemRootController(for: sheetModule)
    }

    func prepareChatSheetRootModelIfNeeded() {
        guard chatSheetRootModel == nil, let sheetRootController, let rootManager = sheetRootController.rootManager else { return }
        chatSheetRootModel = SheetRootModel(
            rootManager: rootManager,
            linkControllable: sheetRootController.linkControllable,
            sheetControllable: sheetRootController.sheetControllable,
            sheetModel: sheetModel,
            isEditor: false
        )
    }

    func close() {
        removeGeneratedEntries(from: sheetModel)
        if let dismissAction {
            dismissAction()
        } else {
            dismiss()
        }
    }

    func commitSelection() {
        let acceptedEntries = acceptedGeneratedEntries
        guard !acceptedEntries.isEmpty else {
            guard sheetModel.hasChanged else { return }
            close()
            return
        }

        commitAcceptedGeneratedEntries()

        if sheetModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sheetModel.name = acceptedEntries.first?.name ?? "Generated Adventure"
        }

        if sheetModel.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sheetModel.description = acceptedEntries.first?.description ?? ""
        }

        removeGeneratedEntries(from: sheetModel)
        close()
    }

    func firstSheetModel(matching source: ItemRowModel, in entries: [SheetModel]) -> SheetModel? {
        for entry in entries {
            if entry.source == source {
                return entry
            }
            if let nestedEntry = firstSheetModel(matching: source, in: entry.entries) {
                return nestedEntry
            }
        }
        return nil
    }

    func makeSheetModel(
        for block: AdventureChatBlockSnapshot,
        index: Int,
        parent: SheetModel,
        batchID: String?,
        entries: [SheetModel] = []
    ) -> SheetModel {
        let typeId: NetworkModules = parent.source.typeId == .none ? .adventure : parent.source.typeId
        let source = ItemRowModel(
            itemId: parent.source.itemId,
            entryId: UUID(),
            typeId: typeId
        )
        let generatedSheet = SheetModel(
            source: source,
            destination: parent.source,
            level: parent.level + 1,
            name: block.titleForSheet(index: index),
            description: block.content,
            entries: entries
        )
        generatedSheet.isGeneratedAnswer = true
        generatedSheet.generatedBatchID = batchID
        return generatedSheet
    }

    func beginAnswerBatch(parent: SheetModel) {
        activeAnswerBatchID = UUID().uuidString
        activeAnswerParent = parent
        activeAnswerParentSource = parent.source
        model.extracted = []
        model.adventureChat = nil
    }

    func updateActiveAnswerBatch() {
        guard previewBlocks == nil, let activeAnswerBatchID, let activeAnswerParent else { return }
        let updatedBlocks = AdventureChatBlockSnapshot.blocks(
            from: model.extracted,
            batchID: activeAnswerBatchID,
            parentSource: activeAnswerParent.source
        )
        activeAnswerParent.entries.removeAll { $0.generatedBatchID == activeAnswerBatchID }
        let newEntries = updatedBlocks.enumerated().map { offset, block in
            makeSheetModel(
                for: block,
                index: activeAnswerParent.entries.count + offset,
                parent: activeAnswerParent,
                batchID: activeAnswerBatchID
            )
        }
        activeAnswerParent.entries.append(contentsOf: newEntries)
    }

    func prepareForNewPrompt() {}

    func requestBlocks(for message: String) {
        beginAnswerBatch(parent: sheetModel)
        let prompt = """
        Create adventure sheet blocks from this request. Return concise blocks with a useful title and playable content. Each block should be suitable for saving into the adventure sheet.

        Request:
        \(message)
        """
        generatorController.extract(message: prompt)
    }

    func targetSheetModel(for source: ItemRowModel) -> SheetModel? {
        if sheetModel.source == source {
            return sheetModel
        }
        return firstSheetModel(matching: source, in: sheetModel.entries)
    }

    func requestDetail(for sheet: SheetModel) {
        let title = sheet.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = sheet.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty || !content.isEmpty else { return }

        beginAnswerBatch(parent: sheet)
        let message = """
        Go deeper on this adventure sheet block and turn it into playable story material.

        This block is already part of the current adventure sheet. Use it as trusted context and expand it into material that still fits the existing adventure.

        Title: \(title.isEmpty ? "Untitled" : title)
        Content: \(content)

        Add scenes, secrets, complications, NPC motives, player choices, and possible outcomes. Return the result as concise saveable adventure sheet blocks.
        """
        generatorController.extract(message: message)
    }

    func extractLatestAnswer() {
        guard let message = extractableMessage else { return }
        beginAnswerBatch(parent: sheetModel)
        generatorController.extract(message: message)
    }

    func installPreviewBlocksIfNeeded() {
        guard !didInstallPreviewBlocks, let previewBlocks else { return }
        didInstallPreviewBlocks = true
        let newEntries = previewBlocks.enumerated().map { offset, block in
            makeSheetModel(
                for: block,
                index: sheetModel.entries.count + offset,
                parent: sheetModel,
                batchID: "preview"
            )
        }
        sheetModel.entries.append(contentsOf: newEntries)
    }

    func generatedEntries(in parent: SheetModel) -> [SheetModel] {
        var entries: [SheetModel] = []
        for entry in parent.entries {
            if entry.isGeneratedAnswer {
                entries.append(entry)
            }
            entries.append(contentsOf: generatedEntries(in: entry))
        }
        return entries
    }

    func commitAcceptedGeneratedEntries() {
        let acceptedEntries = acceptedGeneratedEntriesWithParents(in: sheetModel)
        for acceptedEntry in acceptedEntries {
            guard let editable = entryDataEditable(for: acceptedEntry.parent.source) else { continue }
            let entryId = editable.addNewEntry(itemId: acceptedEntry.parent.source.itemId)
            editable.update(
                itemId: acceptedEntry.parent.source.itemId,
                entryId: entryId,
                name: acceptedEntry.entry.name,
                content: acceptedEntry.entry.description
            )
        }
    }

    func acceptedGeneratedEntriesWithParents(in parent: SheetModel) -> [(parent: SheetModel, entry: SheetModel)] {
        var entries: [(parent: SheetModel, entry: SheetModel)] = []
        for entry in parent.entries {
            if entry.isGeneratedAnswer && entry.isGeneratedAccepted {
                entries.append((parent, entry))
            }
            entries.append(contentsOf: acceptedGeneratedEntriesWithParents(in: entry))
        }
        return entries
    }

    func removeGeneratedEntries(from parent: SheetModel) {
        parent.entries.removeAll { $0.isGeneratedAnswer }
        parent.entries.forEach { removeGeneratedEntries(from: $0) }
    }

    func entryDataEditable(for source: ItemRowModel) -> (any EntryDataEditable)? {
        root.rootManager?.itemRootController(for: source.typeId)?.editControllable as? any EntryDataEditable
    }

    func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func startConversationWithSheetContextIfNeeded() {
        guard !didSendInitialContext else { return }
        didSendInitialContext = true

        guard isChatEffectivelyEmpty, let message = AdventureSheetContextBuilder.initialPrompt(for: sheetModel) else {
            return
        }
        generatorController.request(message: message)
    }

    func generateBlocksFromSheetIfNeeded() {
        guard !didGenerateSheetBlocks else { return }
        didGenerateSheetBlocks = true

        guard previewBlocks == nil, model.extracted.isEmpty,
              let message = AdventureSheetContextBuilder.blockGenerationPrompt(for: sheetModel) else {
            return
        }

        generatorController.extract(message: message)
    }

    var extractableMessage: String? {
        if let adventureChat = model.adventureChat?.trimmingCharacters(in: .whitespacesAndNewlines), !adventureChat.isEmpty {
            return adventureChat
        }

        for entry in model.session.transcript.reversed() {
            if case .response(let response) = entry,
               let text = response.segments.textContentJoined()?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                return text
            }
        }
        return nil
    }

    var isChatEffectivelyEmpty: Bool {
        !model.session.transcript.contains { entry in
            switch entry {
            case .instructions:
                return false
            default:
                return true
            }
        }
    }
}

struct ChatSheetRootView: View {
    let sheetRootController: ItemRootController
    let sheetRootModel: SheetRootModel
    let sheetModel: SheetModel
    @Bindable var model: AdventureSessionModel
    let generatorController: AdventureGeneratorController
    let activeAnswerParentSource: ItemRowModel?
    @Binding var prompt: String
    @FocusState.Binding var isTextFieldFocused: Bool

    let prepareForRequestAction: () -> Void
    let requestBlocksAction: (String) -> Void
    let extractAction: () -> Void
    let requestSheetDetailAction: (SheetModel) -> Void

    private var seedBlocks: [AdventureChatSeedBlock] {
        AdventureSheetContextBuilder.seedBlocks(from: sheetModel)
    }

    private var sourceBlocks: [AdventureChatBlockSnapshot] {
        AdventureSheetContextBuilder.sourceBlocks(from: sheetModel)
    }

    private var generatedCount: Int {
        sheetModel.generatedAnswerCount
    }

    private var selectedCount: Int {
        sheetModel.selectedGeneratedAnswerCount
    }

    private var canExtractLatestAnswer: Bool {
        !(model.adventureChat?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) || !model.session.transcript.isEmpty
    }

    private var currentAnswer: String {
        model.adventureChat?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var isWorking: Bool {
        model.session.isResponding || model.extractSession.isResponding || model.isSummarizing || model.isApplyingWindow
    }

    var body: some View {
        VStack(spacing: 0) {
            TokenUsageBar(
                currentTokenCount: model.currentTokenCount,
                maxContextSize: model.maxContextSize,
                tokenUsageFraction: model.tokenUsageFraction
            )

            AdventureChatHeaderView(
                seedBlocks: seedBlocks,
                sourceCount: sourceBlocks.count,
                generatedCount: generatedCount,
                selectedCount: selectedCount
            )

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    SheetRootView(
                        root: sheetRootController,
                        rootModel: sheetRootModel,
                        detailAction: requestSheetDetailAction
                    ) { sheet in
                        answerSection(for: sheet)
                    }
                }
                .padding()
            }
            .background(.regularMaterial)
            .overlay {
                if showsEmptyState {
                    AdventureNoBlocksView()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            AdventureChatComposerBar(
                prompt: $prompt,
                generatorController: generatorController,
                isTextFieldFocused: $isTextFieldFocused,
                canExtract: canExtractLatestAnswer,
                isExtracting: model.extractSession.isResponding,
                prepareForRequestAction: prepareForRequestAction,
                requestBlocksAction: requestBlocksAction,
                extractAction: extractAction
            )
        }
    }

    @ViewBuilder private func answerSection(for sheet: SheetModel) -> some View {
        let answers = directGeneratedAnswers(in: sheet)
        let selectedCount = selectedCount(in: answers)
        let isTaken = hasHiddenAnswers(in: answers)

        if !answers.isEmpty || showsWorking(for: sheet.source) || showsCurrentAnswer(for: sheet.source) {
            AdventureBlockListSectionHeader(
                title: resultSectionTitle,
                count: answers.count,
                systemImage: "sparkles",
                isWorking: showsWorking(for: sheet.source),
                selectedCount: selectedCount == 0 ? nil : selectedCount,
                isTaken: isTaken,
                canTake: selectedCount > 0,
                takeAction: { takeSelectedAnswers(in: sheet) },
                restoreAction: { restoreAnswers(in: sheet) },
                deleteAction: { deleteAnswers(in: sheet) }
            )
        }

        if directVisibleGeneratedAnswers(in: sheet).isEmpty && showsCurrentAnswer(for: sheet.source) {
            AdventureCurrentAnswerCard(text: currentAnswer)
        }
    }

    private var resultSectionTitle: String {
        "Answers / Ideas"
    }

    private var showsEmptyState: Bool {
        sourceBlocks.isEmpty && generatedCount == 0 && currentAnswer.isEmpty && !isWorking
    }

    private func showsWorking(for parentSource: ItemRowModel) -> Bool {
        isWorking && activeAnswerParentSource == parentSource
    }

    private func showsCurrentAnswer(for parentSource: ItemRowModel) -> Bool {
        activeAnswerParentSource == parentSource && !currentAnswer.isEmpty
    }

    private func directGeneratedAnswers(in sheet: SheetModel) -> [SheetModel] {
        sheet.entries.filter(\.isGeneratedAnswer)
    }

    private func directVisibleGeneratedAnswers(in sheet: SheetModel) -> [SheetModel] {
        directGeneratedAnswers(in: sheet).filter { !$0.isGeneratedHidden }
    }

    private func selectedCount(in answers: [SheetModel]) -> Int {
        answers.filter { $0.isGeneratedSelected && !$0.isGeneratedHidden }.count
    }

    private func hasHiddenAnswers(in answers: [SheetModel]) -> Bool {
        answers.contains(where: \.isGeneratedHidden)
    }

    private func takeSelectedAnswers(in sheet: SheetModel) {
        let answers = directGeneratedAnswers(in: sheet)
        let selectedIDs = Set(answers.filter { $0.isGeneratedSelected && !$0.isGeneratedHidden }.map(\.id))
        guard !selectedIDs.isEmpty else { return }

        withAnimation {
            for answer in answers {
                if selectedIDs.contains(answer.id) {
                    answer.isGeneratedAccepted = true
                    answer.isGeneratedSelected = true
                    answer.isGeneratedHidden = false
                } else {
                    answer.isGeneratedHidden = true
                    answer.isGeneratedSelected = false
                }
            }
        }
    }

    private func restoreAnswers(in sheet: SheetModel) {
        withAnimation {
            for answer in directGeneratedAnswers(in: sheet) {
                answer.isGeneratedHidden = false
                if !answer.isGeneratedAccepted {
                    answer.isGeneratedSelected = false
                }
            }
        }
    }

    private func deleteAnswers(in sheet: SheetModel) {
        withAnimation {
            sheet.entries.removeAll { $0.isGeneratedAnswer }
        }
    }
}

private extension SheetModel {
    var generatedAnswerCount: Int {
        entries.reduce(0) { count, entry in
            count + (entry.isGeneratedAnswer ? 1 : 0) + entry.generatedAnswerCount
        }
    }

    var selectedGeneratedAnswerCount: Int {
        entries.reduce(0) { count, entry in
            count + (entry.isGeneratedSelected && !entry.isGeneratedHidden ? 1 : 0) + entry.selectedGeneratedAnswerCount
        }
    }
}

struct AdventureChatHeaderView: View {
    let seedBlocks: [AdventureChatSeedBlock]
    let sourceCount: Int
    let generatedCount: Int
    let selectedCount: Int

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                AdventureChatMetricPill(value: seedBlocks.count, label: "Context", systemImage: "doc.text")
                AdventureChatMetricPill(value: sourceCount, label: "Sheet Blocks", systemImage: "text.book.closed")
                AdventureChatMetricPill(value: generatedCount, label: "Blocks", systemImage: "square.stack.3d.up")
                AdventureChatMetricPill(value: selectedCount, label: "Selected", systemImage: "checkmark.circle")
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
        .padding()
    }
}

struct AdventureChatMetricPill: View {
    let value: Int
    let label: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(value, format: .number)
            Text(label)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: .rect(cornerRadius: 8))
    }
}

struct AdventureChatComposerBar: View {
    @Binding var prompt: String
    let generatorController: AdventureGeneratorController
    @FocusState.Binding var isTextFieldFocused: Bool
    let canExtract: Bool
    let isExtracting: Bool
    let prepareForRequestAction: () -> Void
    let requestBlocksAction: (String) -> Void
    let extractAction: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ChatInputView(
                messageText: $prompt,
                generatorController: generatorController,
                isTextFieldFocused: $isTextFieldFocused,
                prepareForRequestAction: prepareForRequestAction,
                sendMessageAction: requestBlocksAction
            )

            Button("Extract", systemImage: "list.bullet.clipboard", action: extractAction)
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(!canExtract || isExtracting)
                .padding(.trailing)
                .padding(.bottom)
                .help("Extract adventure blocks")
        }
        .background(.bar)
    }
}

struct AdventureBlockListSectionHeader: View {
    let title: String
    let count: Int
    let systemImage: String
    let isWorking: Bool
    let selectedCount: Int?
    let isTaken: Bool
    let canTake: Bool
    let takeAction: () -> Void
    let restoreAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            if isWorking {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer(minLength: 0)

            if canTake {
                Button("Take", systemImage: "checkmark.circle", action: takeAction)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            if isTaken {
                Button("Restore", systemImage: "arrow.uturn.backward", action: restoreAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }

            if count > 0 {
                Button("Delete Answers", systemImage: "trash", action: deleteAction)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .tint(.red)
                    .help("Delete answers")
            }

            Text(count, format: .number)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let selectedCount {
                Label("\(selectedCount)", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
        }
    }
}

struct AdventureCurrentAnswerCard: View {
    let text: String

    var body: some View {
        Text(text.markDown())
            .font(.callout)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.thinMaterial, in: .rect(cornerRadius: 8))
    }
}

struct AdventureGeneratedBlockRow: View {
    let block: AdventureChatBlockSnapshot
    let isSelected: Bool
    let toggleSelectionAction: () -> Void

    private var title: String {
        block.titleForSheet(index: block.index)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggleSelectionAction) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? .green : .secondary)

                        Text(title)
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if block.isPending {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if !block.content.isEmpty {
                        Text(block.content.markDown())
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    private var borderColor: Color {
        if isSelected {
            return .green
        }
        return .secondary.opacity(0.25)
    }
}

struct AdventureNoBlocksView: View {
    var body: some View {
        ContentUnavailableView(
            "No Blocks",
            systemImage: "square.stack.3d.up",
            description: Text("Sheet blocks and generated blocks will appear here.")
        )
    }
}

enum AdventureChatBlockOrigin: Hashable {
    case sheet
    case generated
}

struct AdventureChatBlockSnapshot: Identifiable, Hashable {
    let id: String
    let index: Int
    let title: String
    let content: String
    let isPending: Bool
    let origin: AdventureChatBlockOrigin
    var source: ItemRowModel? = nil
    var parentSource: ItemRowModel? = nil
    var batchID: String? = nil

    var isEmpty: Bool {
        title.isEmpty && content.isEmpty
    }

    var isSelectable: Bool {
        origin == .generated
    }

    func titleForSheet(index: Int) -> String {
        if title.isEmpty {
            return "Adventure Block \(index + 1)"
        }
        return title
    }

    static func blocks(
        from entries: [BlockEntryGenModel.PartiallyGenerated],
        batchID: String? = nil,
        parentSource: ItemRowModel? = nil
    ) -> [AdventureChatBlockSnapshot] {
        entries.enumerated().map { offset, entry in
            let title = cleaned(entry.title)
            let content = cleaned(entry.content)
            let idPrefix = batchID ?? "preview"
            return AdventureChatBlockSnapshot(
                id: "\(idPrefix)-\(offset)-\(entry.stableID)",
                index: offset,
                title: title,
                content: content,
                isPending: title.isEmpty || content.isEmpty,
                origin: .generated,
                source: nil,
                parentSource: parentSource,
                batchID: batchID
            )
        }
    }

    private static func cleaned(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

struct AdventureChatSeedBlock: Identifiable, Hashable {
    let id: String
    let title: String
    let content: String
    let depth: Int
    let source: ItemRowModel
}

enum AdventureSheetContextBuilder {
    @MainActor
    static func seedBlocks(from sheetModel: SheetModel) -> [AdventureChatSeedBlock] {
        var blocks: [AdventureChatSeedBlock] = []
        collect(from: sheetModel, path: "root", depth: 0, into: &blocks)
        return blocks
    }

    @MainActor
    static func sourceBlocks(from sheetModel: SheetModel) -> [AdventureChatBlockSnapshot] {
        var blocks: [AdventureChatSeedBlock] = []
        collectEntries(from: sheetModel.entries, path: "entry", depth: 1, into: &blocks)

        if blocks.isEmpty {
            let title = cleaned(sheetModel.name)
            let content = cleaned(sheetModel.description)
            if !title.isEmpty || !content.isEmpty {
                blocks.append(
                    AdventureChatSeedBlock(
                        id: "root",
                        title: title.isEmpty ? "Adventure" : title,
                        content: content,
                        depth: 0,
                        source: sheetModel.source
                    )
                )
            }
        }

        return blocks.enumerated().map { offset, block in
            AdventureChatBlockSnapshot(
                id: "sheet-\(block.id)",
                index: offset,
                title: block.title,
                content: block.content,
                isPending: false,
                origin: .sheet,
                source: block.source
            )
        }
    }

    @MainActor
    static func initialPrompt(for sheetModel: SheetModel) -> String? {
        let blocks = seedBlocks(from: sheetModel)
        guard !blocks.isEmpty else { return nil }

        let context = blocks
            .prefix(16)
            .map { block in
                let indent = String(repeating: "  ", count: min(block.depth, 3))
                return "\(indent)- \(block.title): \(truncated(block.content, limit: 320))"
            }
            .joined(separator: "\n")

        return """
        Summarize these existing adventure sheet notes into a compact starting context for our chat. Preserve named places, NPCs, conflicts, secrets, and open story hooks. After the summary, propose the next useful adventure blocks to create.

        Existing sheet:
        \(context)
        """
    }

    @MainActor
    static func blockGenerationPrompt(for sheetModel: SheetModel) -> String? {
        let blocks = sourceBlocks(from: sheetModel)
        guard !blocks.isEmpty else { return nil }

        let sheetText = blocks
            .prefix(20)
            .map { block in
                """
                Title: \(block.titleForSheet(index: block.index))
                Content: \(truncated(block.content, limit: 420))
                """
            }
            .joined(separator: "\n\n")

        return """
        Generate adventure sheet blocks from the following SheetModel text. Preserve the existing meaning, but rewrite each result as a clear playable block with a concise title and useful content. Prefer scenes, story beats, secrets, NPC motives, complications, choices, and outcomes. Return structured blocks suitable for saving back into an adventure sheet.

        SheetModel text:
        \(sheetText)
        """
    }

    @MainActor
    private static func collect(
        from sheetModel: SheetModel,
        path: String,
        depth: Int,
        into blocks: inout [AdventureChatSeedBlock]
    ) {
        let title = cleaned(sheetModel.name)
        let content = cleaned(sheetModel.description)

        if !title.isEmpty || !content.isEmpty {
            blocks.append(
                AdventureChatSeedBlock(
                    id: path,
                    title: title.isEmpty ? "Untitled" : title,
                    content: content,
                    depth: depth,
                    source: sheetModel.source
                )
            )
        }

        for entry in sheetModel.entries.enumerated() {
            collect(from: entry.element, path: "\(path).entry.\(entry.offset)", depth: depth + 1, into: &blocks)
        }

        for entry in sheetModel.inlineEntries.enumerated() {
            collect(from: entry.element, path: "\(path).inline.\(entry.offset)", depth: depth + 1, into: &blocks)
        }
    }

    @MainActor
    private static func collectEntries(
        from entries: [SheetModel],
        path: String,
        depth: Int,
        into blocks: inout [AdventureChatSeedBlock]
    ) {
        for entry in entries.enumerated() {
            let sheet = entry.element
            let title = cleaned(sheet.name)
            let content = cleaned(sheet.description)
            let entryPath = "\(path).\(entry.offset)"

            if !title.isEmpty || !content.isEmpty {
                blocks.append(
                    AdventureChatSeedBlock(
                        id: entryPath,
                        title: title.isEmpty ? "Adventure Block \(blocks.count + 1)" : title,
                        content: content,
                        depth: depth,
                        source: sheet.source
                    )
                )
            }

            collectEntries(from: sheet.entries, path: "\(entryPath).entry", depth: depth + 1, into: &blocks)
        }
    }

    private static func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncated(_ value: String, limit: Int) -> String {
        let value = cleaned(value)
        guard value.count > limit else { return value }
        return "\(value.prefix(limit))..."
    }
}

#Preview("Studio - iPhone", traits: .mockData) {
    NavigationStack {
        AdventureChatPreviewHarness()
            .frame(width: 430, height: 780)
    }
}

struct AdventureChatPreviewHarness: View {
    var body: some View {
        AdventureChatRootView(
            sheetModel: AdventureChatPreviewData.sheetModel,
            usesAvailabilityGate: false,
            previewBlocks: AdventureChatPreviewData.blocks
        )
    }
}

enum AdventureChatPreviewData {
    @MainActor static var sheetModel: SheetModel {
        let firstEntrySource = ItemRowModel(itemId: UUID(), entryId: UUID(), typeId: .adventure)
        let secondEntrySource = ItemRowModel(itemId: UUID(), entryId: UUID(), typeId: .adventure)
        let thirdEntrySource = ItemRowModel(itemId: UUID(), entryId: UUID(), typeId: .adventure)
        let rootSource = ItemRowModel(itemId: UUID(), typeId: .adventure)
        return SheetModel(
            source: rootSource,
            level: 0,
            name: "The Seven Rooms",
            description: "A lost fortress built by dwarves for elven envoys, with each colored hall hiding a political vow.",
            entries: [
                SheetModel(
                    source: firstEntrySource,
                    level: 1,
                    name: "Ruby Gate",
                    description: "The red chamber tests courage through a silent duel against a remembered failure.",
                    entries: []
                ),
                SheetModel(
                    source: secondEntrySource,
                    level: 1,
                    name: "Verdant Archive",
                    description: "The green room preserves the original peace treaty in living roots that answer only honest questions.",
                    entries: []
                ),
                SheetModel(
                    source: thirdEntrySource,
                    level: 1,
                    name: "Indigo Betrayal",
                    description: "The blue-violet hall replays the night an elven diplomat broke the fortress wards to save one child.",
                    entries: []
                )
            ]
        )
    }

    static var blocks: [AdventureChatBlockSnapshot] {
        [
            AdventureChatBlockSnapshot(
                id: "preview-ruby",
                index: 0,
                title: "The Ruby Gate",
                content: "The first room asks each hero to cross a bridge of red glass while whispers name the choice they regret most.",
                isPending: false,
                origin: .generated
            ),
            AdventureChatBlockSnapshot(
                id: "preview-verdant",
                index: 1,
                title: "The Verdant Archive",
                content: "Living vines bind treaty tablets to the walls. Cutting them reveals routes, but preserving them earns an elven spirit guide.",
                isPending: false,
                origin: .generated
            ),
            AdventureChatBlockSnapshot(
                id: "preview-indigo",
                index: 2,
                title: "The Indigo Betrayal",
                content: "A moonlit chamber repeats the night the fortress changed hands, allowing players to question echoes of both sides.",
                isPending: false,
                origin: .generated
            ),
            AdventureChatBlockSnapshot(
                id: "preview-forge",
                index: 3,
                title: "The White Forge",
                content: "The final hall can reforge one broken promise into a magical key, but only if the party agrees what must stay lost.",
                isPending: false,
                origin: .generated
            )
        ]
    }
}
