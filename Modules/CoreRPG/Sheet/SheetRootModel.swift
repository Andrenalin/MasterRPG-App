// @copyright André Trettin

import SwiftUI

enum LinkHighlightTextModelId: Hashable {
    case item(UUID)
    case itemContent(UUID)
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

/// Main-actor coordinator for one recursively rendered RPG sheet.
///
/// A sheet root owns the materialized ``SheetModel`` tree and coordinates
/// presentation state that must remain consistent across every recursive row:
/// search, exclusive selection, viewer quick editing, link expansion, editing
/// mutations, and transient AI generation previews.
///
/// Domain mutations are delegated to the module controllers reachable through
/// `RootManager`. The model then asks the appropriate `SheetControllable` to
/// reconcile the affected ``SheetModel`` subtree with current domain data.
///
/// `SheetRootModel` is main-actor isolated because it owns observable UI state
/// and mutable ``SheetModel`` reference graphs. Immutable AI requests and
/// snapshots are `Sendable` values that can cross an asynchronous generation
/// boundary before results are installed back on the main actor.
///
/// See `Docu/SHEETS.md` for construction variants, presentation modes, and the
/// complete link, search, editor, AI, and import-review flows.
@MainActor @Observable
public final class SheetRootModel: Sendable {
    public init(rootManager: RootManager, linkControllable: any LinkControllable, sheetControllable: SheetControllable, itemId: UUID, isEditor: Bool, isGameEditor: Bool = false) {
        self.rootManager = rootManager
        self.linkControllable = linkControllable
        self.sheetControllable = sheetControllable
        self.isEditor = isEditor
        self.isGameEditor = isGameEditor
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
        self.isGameEditor = false
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
        self.isGameEditor = false
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
        self.isGameEditor = false
        self.sheetModel = sheetModel
        self.editorModel = SheetEditorModel(itemId: sheetModel.source.itemId, module: sheetModel.source.typeId)
        initializeLastIsShownState(sheetModel: sheetModel)
    }

    let isEditor: Bool
    /// Whether this instance is a live game view that should nonetheless
    /// persist its edits like the standalone editor does — e.g. CharacterRPG's
    /// game view, where "changes on character are saved" even during play
    /// (unlike Map, which must always stay memory-only during a game). Only
    /// `ViewerRootView.gameSheetRootModel` (CharacterRPG's persistent game
    /// slot) sets this `true`; every other instance defaults to `false`.
    let isGameEditor: Bool
    /// Whether edits made through this instance should persist regardless of
    /// an active game — true for the standalone editor, and for game views
    /// deliberately treated as an editor too (see `isGameEditor`).
    var persistsEdits: Bool { isEditor || isGameEditor }
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

    private(set) var inlineEditingEntryId: UUID?

    // MARK: - AI generation

    public private(set) var isAIModeActive: Bool = false
    public var focusAISheetModel: SheetModel? = nil

    public func updateAIPreview(_ entry: SheetModel?) {
        let wasNil = sheetModel.aiPreviewEntry == nil
        sheetModel.aiPreviewEntry = entry
        if wasNil, let entry {
            setScrollEntryId(source: entry.source, entryId: entry.source.itemId)
        }
    }

    public func updateAIGenerated(_ entries: [SheetModel]) {
        let previousCount = sheetModel.aiGeneratedEntries.count
        sheetModel.aiGeneratedEntries = entries
        if entries.count > previousCount, let last = entries.last {
            setScrollEntryId(source: last.source, entryId: last.source.itemId)
        }
    }

    public func clearAIState() {
        sheetModel.aiPreviewEntry = nil
        sheetModel.aiGeneratedEntries = []
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
        inlineEditingEntryId = nil
        isAIModeActive = false
        clearAIState()
        needsExternalReconcile = false
    }

    /// Set when the counterpart `SheetRootModel` for this module — the editor's
    /// `sheetRootModel` if this instance is the game view's `gameSheetRootModel`,
    /// or vice versa (see `ItemEditorModel`) — just reconciled and this item may
    /// be the one it shows. Deliberately cheap: it's just a flag. The actual
    /// reconcile is deferred to `SheetRootView`'s `.onChange`, so an instance
    /// that isn't currently being rendered never pays for it — it catches up
    /// the moment it's shown again. Public (but externally read-only) so other
    /// views hosting a `SheetRootModel` outside `SheetRootView` can opt into the
    /// same deferred-reconcile pattern.
    public private(set) var needsExternalReconcile = false

    /// Called by a counterpart `SheetRootModel` (see `syncCounterpart()`) when
    /// the item it just reconciled might be the one this instance shows.
    public func syncFrom(itemId: UUID) {
        guard sheetModel.source.itemId == itemId else { return }
        needsExternalReconcile = true
    }

    /// Called from `SheetRootView`'s `.onChange(of: needsExternalReconcile)`.
    /// Performs the deferred reconcile from `syncFrom(itemId:)` if one is
    /// pending — a no-op otherwise.
    public func reconcileIfNeeded() {
        guard needsExternalReconcile else { return }
        needsExternalReconcile = false
        performReconcile()
    }

    /// Tells this module's other live sheet slot (editor ↔ game — see
    /// `ItemEditorModel.sheetRootModel`/`gameSheetRootModel`) that this root
    /// item just reconciled, in case it's showing the same item.
    private func syncCounterpart() {
        guard let editorModel = rootController(for: sheetModel.source.typeId)?.editControllable.editorModel else { return }
        let itemId = sheetModel.source.itemId
        if isEditor {
            editorModel.gameSheetRootModel?.syncFrom(itemId: itemId)
        } else {
            editorModel.sheetRootModel?.syncFrom(itemId: itemId)
        }
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
            let model = LinkHighlightTextModel(linkControllable: linkRootController, text: text, highlightedText: searchText, toggler: { self.toggle(id: id, itemId: $0, module: $1, linkNumber: $2) }, shareResult: shareResults)
            linkTextModel[id] = model
            return model
        }
        return model
    }
    
    func toggle(id: LinkHighlightTextModelId, itemId: UUID, module: NetworkModules, linkNumber: Int) {
        withAnimation {
            switch id {
            case .item(let uuid), .itemContent(let uuid):
                _ = toggleItemLink(
                    sheetModel: sheetModel,
                    sourceItemId: uuid,
                    linkId: itemId,
                    module: module,
                    linkNumber: linkNumber
                )
            case .entry(let uuid):
                _ = toggleShown(sheetModel: sheetModel, entryId: uuid, linkId: itemId, module: module, linkNumber: linkNumber)
            case .entryContent(let uuid):
                _ = toggleShown(sheetModel: sheetModel, entryId: uuid, linkId: itemId, module: module, linkNumber: linkNumber)
            }
        }
    }

    func toggleItemLink(
        sheetModel: SheetModel,
        sourceItemId: UUID,
        linkId: UUID,
        module: NetworkModules,
        linkNumber: Int
    ) -> Bool {
        if sheetModel.source.itemId == sourceItemId {
            if let existingSheet = linkedSheet(
                in: sheetModel.entries,
                itemId: linkId,
                linkNumber: linkNumber
            ) {
                unfold(sheetModel: existingSheet)
                existingSheet.isShown.toggle()
                return true
            }
            guard let rootModel = rootManager.rootModel(for: module) else { return false }
            let newSheet = rootModel.sheetControllable.sheet(
                root: rootManager,
                itemId: linkId,
                destination: sheetModel.destination,
                level: sheetModel.level + 1,
                isShown: true,
                moduleDepth: 0,
                isEditor: isEditor
            )
            newSheet.linkNumber = linkNumber
            unfold(sheetModel: newSheet)
            sheetModel.entries.append(newSheet)
            return true
        }
        for entry in sheetModel.entries where toggleItemLink(
            sheetModel: entry,
            sourceItemId: sourceItemId,
            linkId: linkId,
            module: module,
            linkNumber: linkNumber
        ) {
            return true
        }
        return false
    }
    
    func toggleShown(sheetModel: SheetModel, entryId: UUID, linkId: UUID, module: NetworkModules, linkNumber: Int) -> Bool {
        for entrySheetModel in sheetModel.entries {
            // Compare entryId (UUID) with source.entryId or source.itemId
            let matchesEntry = entrySheetModel.source.entryId == entryId || entrySheetModel.source.itemId == entryId
            if matchesEntry {
                if let existingSheet = linkedSheet(
                    in: entrySheetModel.entries,
                    itemId: linkId,
                    linkNumber: linkNumber
                ) {
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
                        newSheet.linkNumber = linkNumber
                        unfold(sheetModel: newSheet)
                        entrySheetModel.entries.append(newSheet)
                        return true
                    }
                }
                return true
            }
            if toggleShown(sheetModel: entrySheetModel, entryId: entryId, linkId: linkId, module: module, linkNumber: linkNumber) {
                return true
            }
        }
        return false
    }

    private func linkedSheet(
        in entries: [SheetModel],
        itemId: UUID,
        linkNumber: Int
    ) -> SheetModel? {
        if let exactMatch = entries.first(where: {
            $0.source.itemId == itemId && $0.linkNumber == linkNumber
        }) {
            return exactMatch
        }

        let unnumberedMatches = entries.filter {
            $0.source.itemId == itemId && $0.linkNumber == nil
        }
        return unnumberedMatches.count == 1 ? unnumberedMatches[0] : nil
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
        if selectedEntryId == entryModel.id,
           selectedEntryModel === entryModel,
           entryModel.isSelected {
            selectedParentModel = parent
            return
        }
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

        if inlineEditingEntryId == entryModel.id {
            entryModel.isEditing = false
            inlineEditingEntryModel?.isEditing = false
            inlineEditingEntryModel = nil
            inlineEditingEntryId = nil
            return
        }

        inlineEditingEntryModel?.isEditing = false
        entryModel.isEditing = true
        inlineEditingEntryModel = entryModel
        inlineEditingEntryId = entryModel.id
    }

    func isInlineEditing(_ entryModel: SheetModel) -> Bool {
        inlineEditingEntryId == entryModel.id
    }

    func updateEditType(
        _ editType: SheetModelEditType,
        for entryModel: SheetModel,
        parent: SheetModel
    ) {
        guard let entryId = entryModel.source.entryId,
              let editable = editControllable(for: entryModel.source) as? any SheetEditTypeControllable,
              editable.supportedSheetEditTypes.contains(editType),
              entryModel.editType != editType else { return }
        editable.updateSheetEditType(
            itemId: entryModel.source.itemId,
            entryId: entryId,
            editType: editType
        )
        entryModel.editType = editType
        updateParent(parent)
    }

    func supportedEditTypes(for source: ItemRowModel) -> [SheetModelEditType] {
        (editControllable(for: source) as? any SheetEditTypeControllable)?
            .supportedSheetEditTypes ?? []
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
    /// Gated on `persistsEdits`, not just `isEditor`: a game view deliberately
    /// treated as an editor too (`isGameEditor`, e.g. CharacterRPG's) should
    /// get the same menu-bar/keyboard-shortcut editing commands.
    var selectedSheetEntryFocusValue: SelectedSheetEntry? {
        guard persistsEdits,
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


    // MARK: - AI generation

    public func setAIModeActive(_ isActive: Bool) {
        guard isAIModeActive != isActive else { return }
        isAIModeActive = isActive
    }

    func commitAIEntry(_ entry: SheetModel, parent: SheetModel) {
        _ = entryDataEditable(for: parent.source)?.insertEntry(
            itemId: parent.source.itemId,
            name: entry.name,
            content: entry.description,
            position: .end,
            forceSave: persistsEdits
        )
        sheetModel.aiGeneratedEntries.removeAll { $0 === entry }
        updateParent(parent)
    }

    // MARK: - Search
    
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
    
    public func removeEntry(entryModel: SheetModel, from parentModel: SheetModel) {
        if entryModel.isGeneratedAnswer {
            sheetModel.aiGeneratedEntries.removeAll { $0 === entryModel }
            return
        }
        entryDataEditable(for: entryModel.source)?.removeEntry(source: entryModel.source, forceSave: persistsEdits)
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
        updateParent(parentModel)
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

    func convertibleGroupCandidates(source: ItemRowModel) -> [FolderRepresentable] {
        guard let entryId = source.entryId, let editable = entryDataEditable(for: source) else { return [] }
        let content = editable.entryContent(itemId: source.itemId, entryId: entryId)
        var seen: Set<UUID> = []
        return LinkReplaceController.links(for: content).compactMap { link -> FolderRepresentable? in
            guard link.entryId == nil,
                  link.module == source.typeId,
                  editable.canBecomeGroup(itemId: link.itemId),
                  seen.insert(link.itemId).inserted else { return nil }
            return FolderRepresentable(id: link.itemId, name: editable.itemControllable.nameSync(itemId: link.itemId))
        }
    }

    @MainActor func convertEntryToGroup(source: ItemRowModel, existingItemId: UUID?) async -> (any ItemDataAccessable)? {
        guard let entryId = source.entryId,
              let editable = entryDataEditable(for: source) else { return nil }
        let groupId = await editable.convertToGroup(itemId: source.itemId, entryId: entryId, existingItemId: existingItemId)
        updateFromRoot()

        // The entry's rendered name now contains a freshly materialized link (or lost one).
        // A cached LinkHighlightTextModel doesn't re-scan on its own when handed new text
        // through `linkTextModel(for:text:)` (it only seeds the cache on first access), so
        // without this the row keeps rendering the pre-conversion text until its view is
        // torn down and rebuilt.
        if let entryModel = findEntryModel(entryId: entryId, in: sheetModel) {
            linkTextModel[.entry(entryId)]?.reset(text: entryModel.name)
            linkTextModel[.entryContent(entryId)]?.reset(text: entryModel.description)
        }

        // Turning an existing item into a hidden group (or creating a new hidden one) only
        // mutates that item's own fields (groupId/displayState) — it doesn't touch
        // itemDataModel.items. ListModelUpdatesViewModifier's observation stream only watches
        // that array, so it never notices, and the item lingers in the root list until an
        // unrelated search rebuilds it. Ask the list explicitly, like ListRootContextMenu's
        // move/add/remove actions already do for the same class of field-only mutation.
        rootController(for: source.typeId)?.folderListControllable.update(debounce: false)

        return editable.itemControllable.itemSync(for: groupId)
    }

    private func findEntryModel(entryId: UUID, in model: SheetModel) -> SheetModel? {
        if model.source.entryId == entryId { return model }
        for entry in model.entries {
            if let found = findEntryModel(entryId: entryId, in: entry) { return found }
        }
        return nil
    }

    public func setScrollEntryId(source: ItemRowModel, entryId: UUID?) {
        guard let editController = editControllable(for: source) else { return }
        editController.editorModel.sheetEditorModel.scrollEntryId = entryId
    }

    private func addNewEntry(to source: ItemRowModel) -> UUID? {
        guard let editable = entryDataEditable(for: source) else { return nil }
        return editable.addNewEntry(itemId: source.itemId, forceSave: persistsEdits)
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
              let newId = editable.copy(itemId: entryModel.source.itemId, entryId: entryId, forceSave: persistsEdits) else { return }
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
        editable.move(itemId: parentModel.source.itemId, entryIds: parentModel.entries.compactMap { $0.source.entryId }, forceSave: persistsEdits)
        if !searchText.isEmpty {
            updateFilteredEntries()
        }
        updateParent(parentModel)
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

        editable.move(itemId: parentModel.source.itemId, entryIds: parentModel.entries.compactMap { $0.source.entryId }, forceSave: persistsEdits)
        if !searchText.isEmpty {
            updateFilteredEntries()
        }
        updateParent(parentModel)
    }

    func moveEntry(fromItemId: UUID, entryId: UUID, toItemId: UUID, afterEntry: SheetModel) {
        guard let sourceEditable = entryDataEditable(for: ItemRowModel(itemId: fromItemId, typeId: afterEntry.source.typeId)) else { return }

        // Move the entry from source item to target item
        let success = sourceEditable.move(itemId: fromItemId, entryId: entryId, into: ItemRowModel(itemId: toItemId, typeId: afterEntry.source.typeId), forceSave: persistsEdits)

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
        editable.move(itemId: entryModel.source.itemId, sourceEntryId: entryId, into: folder, forceSave: persistsEdits)
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
        editable.moveOutOfGroup(itemId: entryModel.source.itemId, sourceEntryId: entryId, parent: parent, forceSave: persistsEdits)
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
        syncCounterpart()
    }

    /// Updates from the root SheetModel down - use when changes may affect calculated values throughout the tree
    public func updateFromRoot() {
        performReconcile()
        syncCounterpart()
    }

    private func performReconcile() {
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
