// @copyright André Trettin

import SwiftUI

enum LinkHighlightTextModelId: Hashable {
    case item(UUID)
    case entry(UUID)
    case entryContent(UUID)
}

enum SheetRowGeometryID: Hashable {
    case regular(parent: UUID, row: UUID)
    case generated(parent: UUID, draft: UUID)
}

struct SheetRowGeometryMatch {
    let id: SheetRowGeometryID
    let isSource: Bool
}

private struct GeneratedAcceptanceKey: Hashable {
    let parentModelID: UUID
    let persistedEntryID: UUID
}

@MainActor @Observable
public final class SheetRootModel: Sendable {
    public init(rootManager: RootManager, linkControllable: any LinkControllable, sheetControllable: SheetControllable, itemId: UUID, isEditor: Bool) {
        self.rootManager = rootManager
        self.linkControllable = linkControllable
        self.sheetControllable = sheetControllable
        self.isEditor = isEditor
        let sheetModel = sheetControllable.sheet(root: rootManager, itemId: itemId, destination: nil, level: 0, isShown: true, moduleDepth: 0, isEditor: isEditor)
        self.sheetModel = sheetModel
        self.editorModel = SheetEditorModel(itemId: itemId, module: sheetModel.source.typeId)
        // Initialize lastIsShown to match isShown so first search clear works correctly
        initializeLastIsShownState(sheetModel: sheetModel)
    }

    public init(rootManager: RootManager, linkControllable: any LinkControllable, sheetControllable: SheetControllable, itemId: UUID, isEditor: Bool, editorModel: SheetEditorModel) {
        self.rootManager = rootManager
        self.linkControllable = linkControllable
        self.sheetControllable = sheetControllable
        self.isEditor = isEditor
        let sheetModel = sheetControllable.sheet(root: rootManager, itemId: itemId, destination: nil, level: 0, isShown: true, moduleDepth: 0, isEditor: isEditor)
        self.sheetModel = sheetModel
        self.editorModel = editorModel
        // Initialize lastIsShown to match isShown so first search clear works correctly
        initializeLastIsShownState(sheetModel: sheetModel)
    }

    /// Builds a materialized import sheet and decorates its direct entries with
    /// non-mutating Existing/Merge/New snapshots. Public construction stays unchanged.
    init(
        rootManager: RootManager,
        linkControllable: any LinkControllable,
        sheetControllable: SheetControllable,
        itemId: UUID,
        module: NetworkModules,
        isEditor: Bool,
        reviewModel: ImportReviewModel,
        reviewItem: ImportReviewItemModel
    ) {
        let reviewRootManager = rootManager.with(reviewSheetMemory: reviewModel.sheetMemory())
        let sheetModel = sheetControllable.sheet(
            root: reviewRootManager,
            itemId: itemId,
            destination: nil,
            level: 0,
            isShown: true,
            moduleDepth: 0,
            isEditor: isEditor
        )

        var versionSheets: [SingleReviewDecision: SheetModel] = [:]
        for decision in SingleReviewDecision.allCases {
            let versionMemory = reviewModel.sheetMemory(
                overriding: itemId,
                module: module,
                decision: decision
            )
            let versionRootManager = rootManager.with(reviewSheetMemory: versionMemory)
            versionSheets[decision] = sheetControllable.sheet(
                root: versionRootManager,
                itemId: itemId,
                destination: nil,
                level: 0,
                isShown: true,
                moduleDepth: 0,
                isEditor: false
            )
        }

        self.rootManager = reviewRootManager
        self.linkControllable = linkControllable
        self.sheetControllable = sheetControllable
        self.isEditor = isEditor
        self.sheetModel = sheetModel
        self.editorModel = SheetEditorModel(itemId: itemId, module: sheetModel.source.typeId)

        SheetReviewTreeBuilder.decorate(
            sheetModel: sheetModel,
            reviewItem: reviewItem,
            versionSheets: versionSheets
        )
        initializeLastIsShownState(sheetModel: sheetModel)
    }

    // Use this init in fake/testing contexts where a real SheetModel tree is already built.
    // FakeSheetController.sheet ignores the root parameter anyway, so passing
    // the SheetModel directly avoids needing a real cross-module sheet() call.
    public init(rootManager: RootManager, linkControllable: any LinkControllable, sheetControllable: SheetControllable, sheetModel: SheetModel, isEditor: Bool) {
        self.rootManager = rootManager
        self.linkControllable = linkControllable
        self.sheetControllable = sheetControllable
        self.isEditor = isEditor
        self.sheetModel = sheetModel
        self.editorModel = SheetEditorModel(itemId: sheetModel.source.itemId, module: sheetModel.source.typeId)
        initializeLastIsShownState(sheetModel: sheetModel)
    }

    let isEditor: Bool
    public let editorModel: SheetEditorModel
    public private(set)var sheetModel: SheetModel
    private var hasActiveSearch: Bool = false

    public var searchText: String = "" {
        didSet {
            let wasEmpty = oldValue.isEmpty
            let isEmpty = searchText.isEmpty

            // Save state when starting search (before filter modifies anything)
            if wasEmpty && !isEmpty {
                saveIsShownState(sheetModel: sheetModel)
                hasActiveSearch = true
            }

            // Determine if we should restore state (when clearing an active search)
            let shouldRestore = !wasEmpty && isEmpty && hasActiveSearch

            // Clear search flag when search is cleared
            if !wasEmpty && isEmpty {
                hasActiveSearch = false
            }

            updateFilteredEntries(shouldRestoreState: shouldRestore)
        }
    }

    /// The id (SheetModel.id) of the exclusively selected row in the tree, if any.
    public private(set) var selectedEntryId: UUID?
    private var selectedEntryModel: SheetModel?
    private var selectedParentModel: SheetModel?

    /// The row whose quick controls are expanded in a non-editor sheet.
    ///
    /// Keeping this at the sheet root gives inline editing one source of truth. It also
    /// lets changing rows close the previous editor in the same state transaction.
    private var inlineEditingEntryModel: SheetModel?

    var inlineEditingEntryId: UUID? {
        inlineEditingEntryModel?.id
    }

    // MARK: - AI generation

    public private(set) var isAIModeActive: Bool = false
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

    @ObservationIgnored let rootManager: RootManager
    @ObservationIgnored let sheetControllable: SheetControllable
    @ObservationIgnored let linkControllable: any LinkControllable
    @ObservationIgnored private var linkTextModel: [LinkHighlightTextModelId: LinkHighlightTextModel] = [:]
    
    /// Reset this model for a new item without replacing the instance.
    /// Callers in other modules (e.g. DetailEditorView in each RPG module) use this
    /// to avoid a @State assignment, which would otherwise re-run DetailEditorView.body
    /// and recreate SheetRootEditorView with a new sheetRootModel reference — causing
    /// SheetRootEditorView to see "@self changed" whenever the async task completed
    /// (which the user perceived as an update "while scrolling").
    public func reset(itemId: UUID) {
        guard sheetModel.source.itemId != itemId else { return }
        // Load the sheet model for the new item first so any search filter
        // that runs afterward operates on the correct data.
        let newSheetModel = sheetControllable.sheet(root: rootManager, itemId: itemId, destination: nil, level: 0, isShown: true, moduleDepth: 0, isEditor: isEditor)
        self.sheetModel = newSheetModel
        self.editorModel.setEdit(source: newSheetModel.source)
        // Clear stale per-item caches so new views build fresh link text models.
        linkTextModel = [:]
        // Clear search state without restoring saved visibility (hasActiveSearch=false
        // means didSet will not attempt a restore when searchText is set to "").
        hasActiveSearch = false
        searchText = ""
        // The old tree (and whatever entry was selected in it) is gone.
        selectedEntryId = nil
        selectedEntryModel = nil
        selectedParentModel = nil
        inlineEditingEntryModel = nil
        pendingGenerationRequest = nil
        pendingGenerationParentModel = nil
        generatedBatch = nil
        generatedBatchParentModel = nil
        generatedAcceptanceTransitions = [:]
        isAIModeActive = false
    }
    
    func rootController(for module: NetworkModules) -> ItemRootController? {
        rootManager.itemRootController(for: module)
    }

    var linkRootController: LinkControllable? {
        rootController(for: .adventure)?.linkControllable
    }
        
    /// Get the correct EditControllable for a source (handles cross-module)
    func editControllable(for source: ItemRowModel) -> (any EditControllable)? {
        rootController(for: source.typeId)?.editControllable
    }

    /// Get the correct EntryDataEditable for a source (handles cross-module)
    func entryDataEditable(for source: ItemRowModel) -> (any EntryDataEditable)? {
        editControllable(for: source) as? (any EntryDataEditable)
    }
    
    func description(for sheetModel: SheetModel) -> String? {
        guard !searchText.isEmpty else { return sheetModel.description }
        return sheetModel.description.localizedCaseInsensitiveContains(searchText) ? sheetModel.description : nil
    }
    
    func linkTextModel(for id: LinkHighlightTextModelId, text: String, shareResults: ShareValueResult? = nil) -> LinkHighlightTextModel {
        guard let model = linkTextModel[id] else {
            let model = LinkHighlightTextModel(linkControllable: linkRootController, text: text, highlightedText: searchText, toggler: { self.toggle(id: id, itemId: $0, module: $1) }, shareResult: shareResults)
            linkTextModel[id] = model
            return model
        }
        return model
    }
    
    func toggle(id: LinkHighlightTextModelId, itemId: UUID, module: NetworkModules) {
        withAnimation {
            switch id {
            case .item:
                break
            case .entry(let uuid):
                _ = toggleShown(sheetModel: sheetModel, entryId: uuid, linkId: itemId, module: module)
            case .entryContent(let uuid):
                _ = toggleShown(sheetModel: sheetModel, entryId: uuid, linkId: itemId, module: module)
            }
        }
    }
    
    func toggleShown(sheetModel: SheetModel, entryId: UUID, linkId: UUID, module: NetworkModules) -> Bool {
        for entrySheetModel in sheetModel.entries {
            // Compare entryId (UUID) with source.entryId or source.itemId
            let matchesEntry = entrySheetModel.source.entryId == entryId || entrySheetModel.source.itemId == entryId
            if matchesEntry {
                if let existingSheet = entrySheetModel.entries.first(where: { $0.source.itemId == linkId }) {
                    unfold(sheetModel: existingSheet)
                    existingSheet.isShown.toggle()
                    return true
                } else {
                    // Link doesn't exist - add it using SheetController
                    if let rootModel = rootManager.rootModel(for: module) {
                        let newSheet = rootModel.sheetControllable.sheet(
                            root: rootManager,
                            itemId: linkId,
                            destination: entrySheetModel.destination,
                            level: entrySheetModel.level + 1,
                            isShown: true,
                            moduleDepth: 0,
                            isEditor: isEditor
                        )
                        unfold(sheetModel: newSheet)
                        entrySheetModel.entries.append(newSheet)
                        return true
                    }
                }
                return true
            }
            if toggleShown(sheetModel: entrySheetModel, entryId: entryId, linkId: linkId, module: module) {
                return true
            }
        }
        return false
    }
    
    func unfold(sheetModel: SheetModel) {
        guard let sheetController = rootManager.rootModel(for: sheetModel.source.typeId)?.sheetControllable else { return }
        sheetController.unfold(root: rootManager, sheetModel: sheetModel)
    }

    // MARK: - Selection

    /// Exclusively selects `entryModel`, clearing whichever entry was previously selected
    /// (anywhere in the tree, including the root sheetModel itself), and scrolls it into view.
    /// `parent` is threaded explicitly by the caller (who already has it in scope) rather than
    /// looked up, since SheetContextMenuView's move-up/down/into-group actions need it too.
    func setSelected(_ entryModel: SheetModel, parent: SheetModel) {
        if let previous = selectedEntryModel, previous !== entryModel {
            previous.isSelected = false
        } else if selectedEntryModel == nil,
                  let selectedEntryId,
                  let previous = findEntry(id: selectedEntryId, in: sheetModel),
                  previous !== entryModel {
            previous.isSelected = false
        }
        entryModel.isSelected = true
        selectedEntryId = entryModel.id
        selectedEntryModel = entryModel
        selectedParentModel = parent
        if let entryId = entryModel.source.entryId {
            // The root/name-row case (entryModel == sheetModel) has no entryId — nothing to scroll to.
            setScrollEntryId(source: entryModel.source, entryId: entryId)
        }
    }

    func clearSelection() {
        guard let selectedEntryId else { return }
        if let selectedEntryModel {
            selectedEntryModel.isSelected = false
        } else {
            findEntry(id: selectedEntryId, in: sheetModel)?.isSelected = false
        }
        self.selectedEntryId = nil
        self.selectedEntryModel = nil
        self.selectedParentModel = nil
    }

    /// Opens or closes the quick controls for an entry in a viewer sheet.
    /// Only one entry can be edited at a time.
    func toggleInlineEditing(_ entryModel: SheetModel, parent: SheetModel) {
        setSelected(entryModel, parent: parent)

        if inlineEditingEntryModel === entryModel {
            entryModel.isEditing = false
            inlineEditingEntryModel = nil
            return
        }

        inlineEditingEntryModel?.isEditing = false
        entryModel.isEditing = true
        inlineEditingEntryModel = entryModel
    }

    func isInlineEditing(_ entryModel: SheetModel) -> Bool {
        inlineEditingEntryModel === entryModel
    }

    /// First non-hidden top-level entry — used to select "into" a sheet from the sidebar list.
    var firstSelectableEntry: SheetModel? {
        sheetModel.entries.first { !$0.isHidden && !$0.isGeneratedHidden }
    }

    /// Selects the next visible top-level entry after the current selection.
    /// Selects the first entry when nothing is currently selected.
    func selectNextEntry() {
        let entries = sheetModel.entries.filter { !$0.isHidden && !$0.isGeneratedHidden }
        guard !entries.isEmpty else { return }
        guard let currentId = selectedEntryId,
              let currentIndex = entries.firstIndex(where: { $0.id == currentId }) else {
            if let first = entries.first { setSelected(first, parent: sheetModel) }
            return
        }
        let nextIndex = currentIndex + 1
        guard nextIndex < entries.count else { return }
        setSelected(entries[nextIndex], parent: sheetModel)
    }

    /// Selects the previous visible top-level entry before the current selection.
    func selectPreviousEntry() {
        let entries = sheetModel.entries.filter { !$0.isHidden && !$0.isGeneratedHidden }
        guard !entries.isEmpty,
              let currentId = selectedEntryId,
              let currentIndex = entries.firstIndex(where: { $0.id == currentId }),
              currentIndex > 0 else { return }
        setSelected(entries[currentIndex - 1], parent: sheetModel)
    }

    /// (parent, entry) pair for menu-bar/Commands consumers — see SelectedSheetEntry.
    var selectedSheetEntryFocusValue: SelectedSheetEntry? {
        guard isEditor,
              let selectedParentModel,
              containsIdentity(selectedParentModel, in: sheetModel),
              let entry = selectedEntry else { return nil }
        return SelectedSheetEntry(rootModel: self, parentModel: selectedParentModel, entryModel: entry, isEditor: isEditor)
    }

    /// The currently selected entry itself, or nil if nothing (or only the root row) is selected.
    public var selectedEntry: SheetModel? {
        guard let selectedEntryId, selectedEntryId != sheetModel.id else { return nil }
        if let selectedEntryModel {
            return containsIdentity(selectedEntryModel, in: sheetModel) ? selectedEntryModel : nil
        }
        return findEntry(id: selectedEntryId, in: sheetModel)
    }

    // MARK: - AI generation

    public func setAIModeActive(_ isActive: Bool) {
        guard isAIModeActive != isActive else { return }
        isAIModeActive = isActive
        if !isActive {
            pendingGenerationRequest = nil
            pendingGenerationParentModel = nil
        }
    }

    private func containsGenerationContent(_ model: SheetModel) -> Bool {
        model.hasGenerationContent ||
        (model.entries + model.inlineEntries).contains(where: containsGenerationContent)
    }

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

    private func findEntry(id: UUID, in model: SheetModel) -> SheetModel? {
        if model.id == id { return model }
        for entry in model.inlineEntries {
            if let found = findEntry(id: id, in: entry) { return found }
        }
        for entry in model.entries {
            if let found = findEntry(id: id, in: entry) { return found }
        }
        return nil
    }

    private func containsIdentity(_ target: SheetModel, in model: SheetModel) -> Bool {
        identityPath(to: target, in: model) != nil
    }

    private func identityPath(to target: SheetModel, in model: SheetModel) -> [SheetModel]? {
        if model === target { return [model] }
        for entry in model.inlineEntries + model.entries {
            if let childPath = identityPath(to: target, in: entry) {
                return [model] + childPath
            }
        }
        return nil
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

    // MARK: - Search

    private func initializeLastIsShownState(sheetModel: SheetModel) {
        sheetModel.lastIsShown = sheetModel.isShown
        sheetModel.entries.forEach { initializeLastIsShownState(sheetModel: $0) }
    }

    private func saveIsShownState(sheetModel: SheetModel) {
        sheetModel.lastIsShown = sheetModel.isShown
        sheetModel.entries.forEach { saveIsShownState(sheetModel: $0) }
    }
    
    private func updateFilteredEntries(shouldRestoreState: Bool = false) {
        _ = sheetModel.filter(searchText: searchText, shouldRestoreState: shouldRestoreState)
        linkTextModel.values.forEach {
            $0.reset(highlightedText: searchText)
        }
    }
    
    // MARK: - Editor
    
    func removeEntry(entryModel: SheetModel, from parentModel: SheetModel) {
        entryDataEditable(for: entryModel.source)?.removeEntry(source: entryModel.source)
        // Use source identifiers to match and remove
        parentModel.entries.removeAll(where: { entry in
            entry.source.itemId == entryModel.source.itemId &&
            entry.source.entryId == entryModel.source.entryId &&
            entry.source.typeId == entryModel.source.typeId
        })
        // Use source identifiers for linkTextModel cleanup
        if let entryId = entryModel.source.entryId {
            linkTextModel[.entry(entryId)] = nil
        } else {
            linkTextModel[.entry(entryModel.source.itemId)] = nil
        }
        updateFilteredEntries()
    }

    /// Update the sheet model after inline edits
    func updateSheetModel(entryModel: SheetModel, updatedText: String) {
        entryModel.description = updatedText
        let lookupId = entryModel.source.entryId ?? entryModel.source.itemId
        linkTextModel[.entry(lookupId)]?.reset(text: entryModel.name)
        linkTextModel[.entryContent(lookupId)]?.reset(text: entryModel.description)
    }
    
    func addNewEntry(in sheetModel: SheetModel) -> UUID? {
        guard let entryId = addNewEntry(to: sheetModel.source) else { return nil }
        //setCurrentItem(source: sheetModel.source, entryId: entryId)
        editorModel.itemId = sheetModel.source.itemId
        editorModel.module = sheetModel.source.typeId
        editorModel.entryId = entryId
        return entryId
    }

    @MainActor func addNewGroup(in sheetModel: SheetModel) async -> UUID? {
        guard let editable = entryDataEditable(for: sheetModel.source) else { return nil }
        let entryId = await editable.addNewGroup(itemId: sheetModel.source.itemId)
        
        //setCurrentItem(source: sheetModel.source, entryId: entryId)
        editorModel.itemId = sheetModel.source.itemId
        editorModel.module = sheetModel.source.typeId
        editorModel.entryId = entryId
        return entryId
    }

    public func setScrollEntryId(source: ItemRowModel, entryId: UUID?) {
        guard let editController = editControllable(for: source) else { return }
        editController.editorModel.sheetEditorModel.scrollEntryId = entryId
    }

    private func addNewEntry(to source: ItemRowModel) -> UUID? {
        guard let editable = entryDataEditable(for: source) else { return nil }
        return editable.addNewEntry(itemId: source.itemId)
    }

    func update(sheetModel: SheetModel, previousEntryId: UUID?, currentEntryId: UUID?) {
        guard let previousEntryId, currentEntryId == nil, editorModel.itemId == sheetModel.source.itemId else { return }

        updateFromRoot()

        guard let entryModel = sheetModel.entries.first(where: { $0.source.entryId == previousEntryId }) else { return }
        entryModel.isEditing = false

        let lookupId = entryModel.source.entryId ?? entryModel.source.itemId
        linkTextModel[.entry(lookupId)]?.reset(text: entryModel.name)
        linkTextModel[.entryContent(lookupId)]?.reset(text: entryModel.description)
    }

    /// Set the current item in the edit controller (keeps ItemEditorModel in sync for scroll/other consumers)
    func setCurrentItem(source: ItemRowModel, entryId: UUID?) {
        guard let editController = editControllable(for: source) else { return }
        editController.setCurrentItem(to: ItemRowTreeModel(itemId: source.itemId, entryId: entryId, typeId: source.typeId))
    }

    // MARK: - Context menu actions

    func duplicateEntry(entryModel: SheetModel, in parentModel: SheetModel) {
        guard let entryId = entryModel.source.entryId,
              let editable = entryDataEditable(for: entryModel.source),
              let newId = editable.copy(itemId: entryModel.source.itemId, entryId: entryId) else { return }
        editorModel.setEdit(source: ItemRowModel(itemId: entryModel.source.itemId, entryId: newId, typeId: entryModel.source.typeId))
        updateParent(parentModel)
    }

    func moveEntry(entryModel: SheetModel, in parentModel: SheetModel, up: Bool) {
        guard let editable = entryDataEditable(for: entryModel.source),
              let index = parentModel.entries.firstIndex(where: { entry in
                  entry.source.itemId == entryModel.source.itemId &&
                  entry.source.entryId == entryModel.source.entryId
              }) else { return }
        let newIndex = up ? index - 1 : index + 2
        guard newIndex >= 0, newIndex <= parentModel.entries.count else { return }
        parentModel.entries.move(fromOffsets: IndexSet(integer: index), toOffset: newIndex)
        editable.move(itemId: parentModel.source.itemId, entryIds: parentModel.entries.compactMap { $0.source.entryId })
        if !searchText.isEmpty {
            updateFilteredEntries()
        }
    }

    func reorderEntry(from sourceIndex: Int, to targetIndex: Int, in parentModel: SheetModel) {
        guard sourceIndex != targetIndex,
              let editable = entryDataEditable(for: parentModel.source),
              sourceIndex >= 0,
              sourceIndex < parentModel.entries.count,
              targetIndex >= 0,
              targetIndex < parentModel.entries.count else { return }

        let entry = parentModel.entries[sourceIndex]
        parentModel.entries.remove(at: sourceIndex)
        let insertIndex = sourceIndex < targetIndex ? targetIndex : targetIndex
        parentModel.entries.insert(entry, at: insertIndex)

        editable.move(itemId: parentModel.source.itemId, entryIds: parentModel.entries.compactMap { $0.source.entryId })
        if !searchText.isEmpty {
            updateFilteredEntries()
        }
    }

    func moveEntry(fromItemId: UUID, entryId: UUID, toItemId: UUID, afterEntry: SheetModel) {
        guard let sourceEditable = entryDataEditable(for: ItemRowModel(itemId: fromItemId, typeId: afterEntry.source.typeId)) else { return }

        // Move the entry from source item to target item
        let success = sourceEditable.move(itemId: fromItemId, entryId: entryId, into: ItemRowModel(itemId: toItemId, typeId: afterEntry.source.typeId))

        guard success else { return }

        // Update the sheet models to reflect the changes
        updateFromRoot()
    }

    func handleDrop<LinkType: LinkDataTransferable>(items: [LinkType], targetEntry: SheetModel, parentModel: SheetModel) -> Bool {
        guard let droppedItem = items.first else { return false }

        if droppedItem.isMove {
            // ===== MOVE: Entry being moved (within same item or across items in same module) =====

            // Only allow moves within same module
            guard droppedItem.module == targetEntry.source.typeId else {
                return false
            }

            // Don't allow dropping on inline entries (like dice, photo, etc.)
            guard targetEntry.sheetType == .item || targetEntry.sheetType == .group else {
                return false
            }

            guard let draggedEntryId = droppedItem.entryId else {
                return false
            }

            // Check if this is a move within the same parent item (reorder)
            if droppedItem.itemId == parentModel.source.itemId,
               let draggedIndex = parentModel.entries.firstIndex(where: { $0.source.entryId == draggedEntryId }),
               let targetIndex = parentModel.entries.firstIndex(where: { entry in
                   entry.source.itemId == targetEntry.source.itemId &&
                   entry.source.entryId == targetEntry.source.entryId
               }),
               draggedIndex != targetIndex {
                // Reorder within same parent
                withAnimation {
                    reorderEntry(from: draggedIndex, to: targetIndex, in: parentModel)
                }
                return true
            }

            // Otherwise, move entry from one item to another (cross-item move)
            if droppedItem.itemId != targetEntry.source.itemId {
                withAnimation {
                    moveEntry(
                        fromItemId: droppedItem.itemId,
                        entryId: draggedEntryId,
                        toItemId: targetEntry.source.itemId,
                        afterEntry: targetEntry
                    )
                }
                return true
            }

            return false

        } else {
            // ===== LINK DROP: From inspector or viewer mode =====

            // Only allow link drops on item entries (not groups, not inline entries)
            guard targetEntry.sheetType == .item else {
                return false
            }

            items.forEach {
                addLink(link: $0.name, module: $0.module, itemId: $0.itemId, entryId: $0.entryId, to: targetEntry, in: parentModel)
            }
            return true
        }
    }

    func groupFolders(for entryModel: SheetModel) -> [FolderRepresentable] {
        guard let entryId = entryModel.source.entryId,
              let editable = entryDataEditable(for: entryModel.source) else { return [] }
        return editable.groupFolders(itemId: entryModel.source.itemId, sourceEntryId: entryId)
    }

    func moveEntry(_ entryModel: SheetModel, in parentModel: SheetModel, into folder: FolderRepresentable) {
        guard let entryId = entryModel.source.entryId,
              let editable = entryDataEditable(for: entryModel.source) else { return }
        editable.move(itemId: entryModel.source.itemId, sourceEntryId: entryId, into: folder)
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            updateParent(parentModel)
        }
    }

    func parentGroup(for entryModel: SheetModel) -> FolderRepresentable? {
        entryDataEditable(for: entryModel.source)?.parentFolder(itemId: entryModel.source.itemId)
    }

    func moveEntryOutOfGroup(_ entryModel: SheetModel, in parentModel: SheetModel, parent: FolderRepresentable) {
        guard let entryId = entryModel.source.entryId,
              let editable = entryDataEditable(for: entryModel.source) else { return }
        editable.moveOutOfGroup(itemId: entryModel.source.itemId, sourceEntryId: entryId, parent: parent)
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            updateParent(parentModel)
        }
    }

    func addLink(link: String, module: NetworkModules, itemId: UUID, entryId: UUID?, to destination: SheetModel, in parentModel: SheetModel) {
        guard let editable = entryDataEditable(for: destination.source),
              let destinationEntryId = destination.source.entryId else { return }
        editable.add(link: link, module: module, itemId: itemId, entryId: entryId, destinationItemId: destination.source.itemId, destinationEntryId: destinationEntryId)
        updateParent(parentModel)
    }

    /// Re-synchronizes the currently edited parent after a module-specific bulk editor saves.
    public func updateParent() {
        guard let parentModel = editorModel.parentModel else { return }
        updateParent(parentModel)
    }
    
    /// Re-syncs a SheetModel tree from live data, then invalidates linkTextModel cache for any entry
    /// whose content changed (hasChanged) and clears the flag.
    func updateParent(_ parentModel: SheetModel) {
        if parentModel.source.typeId == .value {
            updateFromRoot()
            return
        }
        rootController(for: parentModel.source.typeId)?.sheetControllable.update(root: rootManager, sheetModel: parentModel, isEditor: isEditor)
        resetChangedLinkModels(in: parentModel)
        if !searchText.isEmpty {
            updateFilteredEntries()
        }
    }

    /// Updates from the root SheetModel down - use when changes may affect calculated values throughout the tree
    func updateFromRoot() {
        rootController(for: sheetModel.source.typeId)?.sheetControllable.update(root: rootManager, sheetModel: sheetModel, isEditor: isEditor)
        resetChangedLinkModels(in: sheetModel)
        if !searchText.isEmpty {
            updateFilteredEntries()
        }
    }

    private func resetChangedLinkModels(in sheetModel: SheetModel) {
        if sheetModel.hasChanged {
            let lookupId = sheetModel.source.entryId ?? sheetModel.source.itemId
            linkTextModel[.item(sheetModel.source.itemId)]?.reset(text: sheetModel.name)
            linkTextModel[.entry(lookupId)]?.reset(text: sheetModel.description)
            linkTextModel[.entryContent(lookupId)]?.reset(text: sheetModel.description)
            sheetModel.hasChanged = false
        }
        for entry in sheetModel.entries {
            if entry.hasChanged {
                let lookupId = entry.source.entryId ?? entry.source.itemId
                linkTextModel[.entry(lookupId)]?.reset(text: entry.name)
                linkTextModel[.entryContent(lookupId)]?.reset(text: entry.description)
                entry.hasChanged = false
            }
            for subEntry in entry.entries {
                resetChangedLinkModels(in: subEntry)
            }
        }
    }
}
