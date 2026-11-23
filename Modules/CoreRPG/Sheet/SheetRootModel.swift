// @copyright André Trettin

import SwiftUI

/// The key of a cached link text model. The id is the item's or entry's, and `occurrence` is the
/// `SheetModel.id` of the row it is shown in: the same item can appear in several branches of one
/// sheet, and a link tapped in one copy must act on that copy. The cache is cleaned and reset by
/// source id (`resetLinkText`, `removeLinkText`), which reaches every occurrence.
/// See CODE_AUDIT_28 §5.11.
enum LinkHighlightTextModelId: Hashable {
    case item(UUID, occurrence: UUID? = nil)
    case itemContent(UUID, occurrence: UUID? = nil)
    case entry(UUID, occurrence: UUID? = nil)
    case entryContent(UUID, occurrence: UUID? = nil)

    enum Kind: Hashable {
        case item, itemContent, entry, entryContent
    }

    var kind: Kind {
        switch self {
        case .item: .item
        case .itemContent: .itemContent
        case .entry: .entry
        case .entryContent: .entryContent
        }
    }

    var sourceId: UUID {
        switch self {
        case .item(let id, _), .itemContent(let id, _), .entry(let id, _), .entryContent(let id, _): id
        }
    }

    var occurrence: UUID? {
        switch self {
        case .item(_, let occurrence), .itemContent(_, let occurrence), .entry(_, let occurrence), .entryContent(_, let occurrence): occurrence
        }
    }
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
    public internal(set) var selectedEntryId: UUID?
    var selectedEntryModel: SheetModel?
    var selectedParentModel: SheetModel?

    /// The row whose quick controls are expanded in a non-editor sheet.
    ///
    /// Keeping this at the sheet root gives inline editing one source of truth. It also
    /// lets changing rows close the previous editor in the same state transaction.
    var inlineEditingEntryModel: SheetModel?

    var inlineEditingEntryId: UUID?

    // MARK: - AI generation

    public internal(set) var isAIModeActive: Bool = false
    public var focusAISheetModel: SheetModel? = nil

    @ObservationIgnored let rootManager: RootManager
    @ObservationIgnored let sheetControllable: SheetControllable
    @ObservationIgnored let linkControllable: any LinkControllable
    @ObservationIgnored var linkTextModel: [LinkHighlightTextModelId: LinkHighlightTextModel] = [:]
    /// Cancel-then-replace slot for the deferred reconcile after a cross-group entry
    /// move — shared by `moveEntry(_:in:into:)`/`moveEntryOutOfGroup(_:in:parent:)` so a
    /// rapid second move cancels the first move's still-pending reconcile instead of
    /// leaving it running uncancelled. See CODE_AUDIT_Sheet §9.2.
    @ObservationIgnored var pendingGroupMoveTask: Task<Void, Never>?
    /// Cancel-then-replace slots (keyed by parent id), coalescing repeated
    /// `updateParent(_:)` calls fired from `SheetEntryView`'s own
    /// `.onChange(of: name/description)` when several sibling entries under the same
    /// parent change within one external reconcile. See CODE_AUDIT_Sheet §7.1.
    @ObservationIgnored var pendingParentReconcileTasks: [UUID: Task<Void, Never>] = [:]

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
        // The debounced reconciles only refresh the old item's sheet tree (the edits themselves
        // were already written), so they must not run against the new item. See CODE_AUDIT §3.5.
        pendingGroupMoveTask?.cancel()
        pendingGroupMoveTask = nil
        for task in pendingParentReconcileTasks.values { task.cancel() }
        pendingParentReconcileTasks = [:]
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
    func syncCounterpart() {
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
}
