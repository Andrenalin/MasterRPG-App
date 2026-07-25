// @copyright André Trettin

import CoreRPG
import FoundationModels
import SwiftUI

struct AdventureChatRootView: View {
    let sheetModel: SheetModel
    var dismissAction: (() -> Void)? = nil

    private let usesAvailabilityGate: Bool
    private let runsAutomaticGeneration: Bool
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
        runsAutomaticGeneration: Bool = true,
        previewBlocks: [AdventureChatBlockSnapshot]? = nil
    ) {
        self.sheetModel = sheetModel
        self.dismissAction = dismissAction
        self.usesAvailabilityGate = usesAvailabilityGate
        self.runsAutomaticGeneration = runsAutomaticGeneration
        self.previewBlocks = previewBlocks
    }

    private var model: AdventureSessionModel {
        generatorController.model
    }

    private var generatorController: AdventureGeneratorController {
        root.generatorController(for: sheetModule, itemId: sheetModel.source.itemId)
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
                Button(
                    LocalizedStringResource("Close", bundle: .module),
                    systemImage: "xmark",
                    action: close
                )
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(
                    LocalizedStringResource("Save", bundle: .module),
                    systemImage: "checkmark",
                    action: commitSelection
                )
                    .disabled(acceptedGeneratedEntries.isEmpty && !sheetModel.hasChanged)
            }
        }
        .navigationTitle(navigationTitle)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

#Preview("Adventure Chat", traits: .mockData) {
    NavigationStack {
        AdventureChatRootView(
            sheetModel: AdventureChatPreviewData.sheetModel,
            usesAvailabilityGate: false,
            runsAutomaticGeneration: false,
            previewBlocks: AdventureChatPreviewData.blocks
        )
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
            Text("Error", bundle: .module),
            isPresented: $model.showError,
            actions: { Button { model.dismissError() } label: { Text("OK", bundle: .module) } },
            message: { Text(verbatim: model.responseErrorContent) }
        )
        .task {
            prepareChatSheetRootModelIfNeeded()
            installPreviewBlocksIfNeeded()
            guard runsAutomaticGeneration else { return }
            generatorController.generateExtractor()
            await generatorController.generate()
            try? await Task.sleep(for: .seconds(0.5))
            isTextFieldFocused = true
        }
        .onChange(of: model.extracted.map { "\($0.stableID)-\(String(describing: $0.title))-\(String(describing: $0.content))" }) { _, _ in
            updateActiveAnswerBatch()
        }
        .onDisappear {
            guard runsAutomaticGeneration else { return }
            generatorController.tearDown()
        }
    }

    var acceptedGeneratedEntries: [SheetModel] {
        generatedEntries(in: sheetModel).filter(\.isGeneratedAccepted)
    }

    var navigationTitle: String {
        let title = sheetModel.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? String(localized: "Adventure", bundle: .module) : title
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
            sheetModel.name = acceptedEntries.first?.name
                ?? String(localized: "Generated Adventure", bundle: .module)
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
        let trace = PerformanceTrace.begin(
            "GeneratedBlocksRebuild",
            source: "FoundationExtraction",
            count: model.extracted.count
        )
        defer { trace?.end() }
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
            return String(localized: "Adventure Block \(index + 1)", bundle: .module)
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
                        title: title.isEmpty
                            ? String(localized: "Adventure", bundle: .module)
                            : title,
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
                    title: title.isEmpty
                        ? String(localized: "Untitled", bundle: .module)
                        : title,
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
                        title: title.isEmpty
                            ? String(
                                localized: "Adventure Block \(blocks.count + 1)",
                                bundle: .module
                            )
                            : title,
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

enum AdventureChatPreviewData {
    nonisolated static let rootItemID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x90, 0x01))
    nonisolated static let rubyItemID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x90, 0x02))
    nonisolated static let verdantItemID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x90, 0x03))
    nonisolated static let indigoItemID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x90, 0x04))
    nonisolated static let rubyEntryID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x90, 0x12))
    nonisolated static let verdantEntryID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x90, 0x13))
    nonisolated static let indigoEntryID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x90, 0x14))

    @MainActor static var sheetModel: SheetModel {
        let firstEntrySource = ItemRowModel(itemId: rubyItemID, entryId: rubyEntryID, typeId: .adventure)
        let secondEntrySource = ItemRowModel(itemId: verdantItemID, entryId: verdantEntryID, typeId: .adventure)
        let thirdEntrySource = ItemRowModel(itemId: indigoItemID, entryId: indigoEntryID, typeId: .adventure)
        let rootSource = ItemRowModel(itemId: rootItemID, typeId: .adventure)
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
