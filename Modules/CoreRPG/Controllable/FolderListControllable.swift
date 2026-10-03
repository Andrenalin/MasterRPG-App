// @copyright André Trettin

import Foundation
import SwiftUI
import os

/// Distinguishes the two search targets the single search pipeline can run.
enum FolderSearchKind: Sendable { case root, detail }

@MainActor
public protocol FolderListControllable: Sendable {
    var itemControllable: any ItemControllable { get }

    var listModel: FolderListModel { get }
    var listDisplayModel: ListDisplayModel { get }
    var searchModel: SearchModel { get }
    var cacheListItemModel: CacheItemListModel { get }
    var searchRootControllable: any SearchRootControllable { get }

    /// Every module's `FolderListController` conformer shares this exact shape
    /// (a plain memberwise init over these four stored properties, with
    /// `cacheListItemModel` defaulted) — declared here purely so the
    /// `copy(listModel:)` default below can construct a fresh `Self`. See
    /// CODE_AUDIT §9.4.
    init(listModel: FolderListModel, listDisplayModel: ListDisplayModel, itemControllable: any ItemControllable, searchRootControllable: any SearchRootControllable)

    func copy(listModel: FolderListModel) -> Self

    func detailDestination(for itemId: UUID) -> any NavigationDestination
    func folderDestination(for itemId: UUID) -> any NavigationDestination
    func folderInlineDestination(for itemId: UUID) -> any NavigationDestination
    func viewerDestination(for itemId: UUID) -> any NavigationDestination
}

extension FolderListControllable {
    public var searchModel: SearchModel { searchRootControllable.searchModel }

    /// Default `copy(listModel:)` — identical across every module: a fresh
    /// `listDisplayModel`/`searchRootControllable` via `copiedListDependencies`,
    /// this controller's own `itemControllable` reused, and only the passed
    /// `listModel` new. Was hand-copied verbatim into 12 modules' own
    /// `FolderListController`; only the `init` requirement above needed adding
    /// to hoist it here. See CODE_AUDIT §9.4.
    public func copy(listModel: FolderListModel) -> Self {
        let dependencies = copiedListDependencies
        return Self(
            listModel: listModel,
            listDisplayModel: dependencies.listDisplayModel,
            itemControllable: itemControllable,
            searchRootControllable: dependencies.searchRootControllable
        )
    }

    /// The `(listDisplayModel, searchRootControllable)` pair every module's
    /// `copy(listModel:)` derived identically — a fresh display model, and the
    /// search controller copied to match it — before constructing its own
    /// concrete `Self` with those plus the passed `listModel`. Each conformer's
    /// stored-property shape/initializer still differs, so only this shared
    /// derivation is hoisted here, not the `Self` construction itself.
    public var copiedListDependencies: (listDisplayModel: ListDisplayModel, searchRootControllable: any SearchRootControllable) {
        let copiedDisplayModel = listDisplayModel.newListDisplayModel
        return (copiedDisplayModel, searchRootControllable.copy(listDisplayModel: copiedDisplayModel))
    }
    
    /// Runs a search, updates `searchModel.results`, and rebuilds `listModel.list`.
    /// Structured: if the enclosing `Task` is cancelled (e.g. view disappears or a
    /// newer search fires), this function exits at the next cancellation check and
    /// leaves the current list unchanged.
    @MainActor public func performSearch(source: String) async {
        let startTime = ContinuousClock.now
        let searchText = searchModel.searchText
        let displayMode = listDisplayModel.displayMode
        let trace = PerformanceTrace.begin("ListSearch", source: source, count: searchText.count)
        defer { trace?.end() }
        
        Logger.folderListControllable.info("🔍 [Search] Starting ASYNC search - source: '\(source)', text: '\(searchText, privacy: .private)', displayMode: \(displayMode.rawValue)")

        searchModel.searchGeneration &+= 1
        let generation = searchModel.searchGeneration
        searchModel.isSearching = true
        defer {
            // Only the latest search clears the flag; an older one finishing late must not.
            if searchModel.searchGeneration == generation {
                searchModel.isSearching = false
            }
        }

        let newResults = await searchRootControllable.results(text: searchText)
        guard !Task.isCancelled else {
            Logger.folderListControllable.info("⚠️ [Search] Cancelled - source: '\(source)', text: '\(searchText, privacy: .private)'")
            return
        }
        // A newer search started while this one ran (possibly one outside `currentTask`, such
        // as the first-appearance search): its results win. See CODE_AUDIT_Folder §3.19.
        guard searchModel.searchGeneration == generation else {
            Logger.folderListControllable.info("⚠️ [Search] Superseded - source: '\(source)', text: '\(searchText, privacy: .private)'")
            return
        }
        searchModel.results = newResults
        searchModel.searchReturnedNoResults = !searchModel.searchText.isEmpty && newResults.isEmpty
        withAnimation { resetFilter() }
        
        let duration = ContinuousClock.now - startTime
        Logger.folderListControllable.info("✅ [Search] Completed ASYNC - source: '\(source)', text: '\(searchText, privacy: .private)', displayMode: \(displayMode.rawValue), duration: \(duration), results: \(newResults.count)")
    }

    /// Single coalescing entry point for every search trigger. Assigning `searchModel.currentTask`
    /// cancels any in-flight search (its `didSet`), so rapid triggers — keystrokes, mode toggles,
    /// and the observation stream — collapse into one search instead of one-per-event.
    /// `ListSearchTiming.typingDebounce` applies only while typing a non-empty query; every
    /// other trigger uses `ListSearchTiming.coalesceWindow` so bursts still settle into a
    /// single call.
    @MainActor func runSearch(source: String, kind: FolderSearchKind, debounceText: Bool) {
        searchModel.currentTask = Task(name: "List Search") {
            let delay: Duration = debounceText && !searchModel.searchText.isEmpty ? ListSearchTiming.typingDebounce : ListSearchTiming.coalesceWindow
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled else { return }
            switch kind {
            case .root: await performSearch(source: source)
            case .detail: await performDetailSearch()
            }
        }
    }

    /// Fire-and-forget root search for call sites that cannot `await` (e.g. synchronous
    /// protocol-extension callbacks like `resetParent`, `toggleFolder`, and the search field).
    @MainActor func scheduleSearch() {
        runSearch(source: "scheduleSearch", kind: .root, debounceText: true)
    }

    /// Runs a scoped search for the detail list's parent and populates
    /// `listModel.detailListModel.list` with the results.
    ///
    /// Uses `results(text:)` with `filterId = parentModel.id` — the same pipeline as
    /// `performSearch` / `scheduleSearch`. This routes through `inspectorSearchResults`
    /// which correctly handles per-module overrides (e.g. CharacterRPG `focusedCharacterInspector`
    /// returns the character as a root item with entries as children).
    ///
    /// `results(text:, focusId:)` is NOT used here because that path is reserved for
    /// `loadChildrenViaSearch` where the expected return is flat entry/child results —
    /// not an item-as-root structure.
    @MainActor public func performDetailSearch() async {
        guard let detailListModel = listModel.detailListModel,
              let parentModel = detailListModel.parentModel else { return }
        let parentId = parentModel.id
        let trace = PerformanceTrace.begin(
            "DetailListSearch",
            source: "detail",
            count: searchModel.searchText.count
        )
        defer { trace?.end() }
        // scopedResults — semantically "show this item as the root of the detail view":
        //   SearchListController: folder-mode listSearchResults(focusId:) → parent's children.
        //   SearchLinkController: list-mode inspectorSearchResults(focusId:) → character-as-root
        //     (via focusedCharacterInspector) or collection children (via inspectorScopedListResults).
        // Does NOT use results(text:, focusId:) which is exclusively for loadChildrenViaSearch.
        let newResults = await searchRootControllable.scopedResults(
            text: searchModel.searchText,
            focusId: parentId
        )
        guard !Task.isCancelled else { return }
        // Discard a stale write-back: `resetDetail` reuses the same `detailListModel` instance
        // across folder switches (mutating its `parentModel` in place) rather than replacing it,
        // so a slower search started for a previous parent can otherwise resolve after a newer
        // one and silently overwrite the UI with the wrong folder's children.
        guard listModel.detailListModel === detailListModel,
              detailListModel.parentModel?.id == parentId else { return }
        searchModel.detailResults = newResults
        detailListModel.list = buildDetailListItems()
    }
}

public extension FolderListControllable {
    /// Data-change refresh (observation stream, context-menu moves). Routes the search through the
    /// single `currentTask` so it coalesces with — and never clobbers — an in-flight user search,
    /// then applies selection/scroll fix-up only after the (coalesced) search has rebuilt the list.
    /// - `debounce`: the observation stream passes `true` to coalesce bursts; explicit user actions
    ///   (context-menu move/add/remove) pass `false` so the list rebuilds immediately and reliably.
    func update(debounce: Bool = true) {
        let previousSelectedId = listModel.selectedItemId
        let selectionGeneration = listModel.selectionGeneration
        if let addedModelId = listModel.addedModelId,
           let addedItem = listModel.list.first(where: { $0.source.itemId == addedModelId }) {
            listModel.selected = addedItem.id
        }

        searchModel.currentTask = Task(name: "List Data Refresh") {
            if debounce {
                // Coalesce a burst of data changes into one search.
                do { try await Task.sleep(for: ListSearchTiming.coalesceWindow) } catch { return }
            }
            guard !Task.isCancelled else { return }
            // Always refresh the root results: resetFilter rebuilds listModel.list from
            // searchModel.results, so a move/add/remove must re-run performSearch to drop the item
            // from the root level. (Routing only to performDetailSearch left listModel.list rebuilt
            // from stale results — the moved item stayed at its old root position.)
            await performSearch(source: "update")
            // Additionally refresh an active scoped detail list (e.g. the focused character
            // inspector), whose rows come from detailResults rather than the root results.
            if listModel.detailListModel != nil {
                guard !Task.isCancelled else { return }
                await performDetailSearch()
            }
            guard !Task.isCancelled else { return }
            applyPostUpdateSelection(
                previousSelectedId: previousSelectedId,
                selectionGeneration: selectionGeneration
            )
        }
    }

    /// Restores selection/scroll after `update()`'s search has rebuilt the list.
    func applyPostUpdateSelection(
        previousSelectedId: UUID?,
        selectionGeneration: Int
    ) {
        guard listModel.selectionGeneration == selectionGeneration else { return }
        if let addedModelId = listModel.addedModelId,
           let addedItem = listModel.list.first(where: { $0.source.itemId == addedModelId }) {
            let selectedWhenScheduled = listModel.selected
            Task(name: "List Selection Restore") { @MainActor in
                // A render delay for the new row, not a synchronisation point.
                try? await Task.sleep(for: ListSearchTiming.selectionRestoreRenderDelay)
                // Re-check: a second, newer update may have advanced the generation while this
                // delayed task was sleeping — don't clobber a newer selection with a stale one.
                guard listModel.selectionGeneration == selectionGeneration else { return }
                // Nor a row the user selected meanwhile. See CODE_AUDIT_Folder §3.15.
                guard listModel.selected == selectedWhenScheduled || listModel.selected == addedItem.id else { return }
                listModel.listSelection = Set(arrayLiteral: addedItem.id)
            }
            listModel.addedModelId = nil
        } else if let itemId = previousSelectedId ?? listModel.navigationModel.selectedItemId,
                  let newSelected = listModel.list.first(where: { $0.source.itemId == itemId }) {
            listModel.listSelection = Set(arrayLiteral: newSelected.id)
            listModel.selected = newSelected.id
            listModel.scrollId = listModel.restoredScrollTarget(
                selection: newSelected.id,
                prioritizesSelection: !searchModel.searchText.isEmpty
            )
        }
    }
    
    func copyModel(parentModel: (any ItemDataAccessible)?) -> FolderListModel {
        let newModel = FolderListModel(parentModel: parentModel, navigationModel: listModel.navigationModel)
        // Pre-populate the cache with any already-loaded children of the parent folder/collection
        // so the detail list can render immediately while the background search runs.
        if let parentModel {
            for entry in parentModel.entries {
                // Children are keyed by entry.id (folder membership identity)
                if let cached = listModel.cacheListModels[entry.id] {
                    newModel.cacheListModels[entry.id] = cached
                }
                // Also try childId for items cached in list mode (id == itemId)
                let childId = entry.childId
                if childId != entry.id, let cached = listModel.cacheListModels[childId] {
                    newModel.cacheListModels[childId] = cached
                }
            }
        }
        return newModel
    }

    func resetItemOnce() async {
        guard listModel.updatedOnce == false else { return }
        listModel.updatedOnce = true
        await performSearch(source: "resetItemOnce")
    }

    func resetParent(model: (any ItemDataAccessible)?) {
        listModel.resetParent(model: model)
        listModel.updatedOnce = true
        // Scope the next search to this folder/collection's direct children
        searchRootControllable.searchModel.filterId = model?.id
        
        if let model {
            listDisplayModel.listMode <=> model.category == .folder ? .folder : .list
        }
        scheduleSearch()
    }
    
    /// Called when a folder/collection is selected as the detail page's parent.
    /// Creates (or resets) `listModel.detailListModel` scoped to `model`, then populates it.
    ///
    /// The initial populate runs in its own task rather than the shared search token: the sibling
    /// initial triggers (`listMode`/`displayMode` `onChange(initial:)` and the observation stream)
    /// assign `currentTask` around the same time and would otherwise cancel this first populate
    /// before the detail list is ever built — the cause of the focused inspector being blank on
    /// first launch. Subsequent filter-field searches still go through the coalescing pipeline.
    /// The detail cache is warm-started in `copyModel`, so revisited parents redisplay instantly.
    func resetDetail(model: (any ItemDataAccessible)) {
        listModel.resetDetailList(parentModel: model)
        listModel.detailListModel?.updatedOnce = true
        Task(name: "Initial Detail Search") { await performDetailSearch() }
    }

    /// Fire-and-forget scoped detail search — used by `LinkItemListView` / `resetDetail` when
    /// `parentModel != nil`. Routes through the single coalescing pipeline (`runSearch`).
    @MainActor func scheduleDetailSearch() {
        runSearch(source: "scheduleDetailSearch", kind: .detail, debounceText: true)
    }

    func selectedModel(for selectedId: UUID?) -> (any ItemDataAccessible)? {
        itemControllable.itemSync(for: selectedId ?? listModel.selected ?? UUID())
    }

    /// Routes to `detailListModel` when a parent scope is active (`parentModel != nil`);
    /// otherwise the root `listModel`. `ListRootView` and `LinkItemListView` both need this
    /// exact routing so scoped inspector state (entries, open/close, scroll) stays independent
    /// from the unscoped view.
    func scopedListModel(parentModel: (any ItemDataAccessible)?) -> FolderListModel {
        if parentModel != nil, let detail = listModel.detailListModel {
            return detail
        }
        return listModel
    }

    /// True when the "no results" overlay should be shown.
    ///
    /// Uses `searchModel.searchReturnedNoResults` rather than `listModel.list.isEmpty`: `buildList`
    /// deliberately preserves the previous list when a search returns nothing (anti-flicker), so
    /// `list.isEmpty` is never true even when the search matched zero items. The flag is set by
    /// the single search pipeline, so it always reflects the active (and only) in-flight search.
    var shouldShowNoResults: Bool {
        searchModel.searchReturnedNoResults
    }
}

// MARK: List change

extension FolderListControllable {
    /// Creates an item, folder or collection and selects it. The target parent is captured up
    /// front rather than re-read from `listModel` at completion — otherwise a folder-selection
    /// change during the multi-step async chain below could silently file the new item under
    /// whatever folder happened to be selected when the task finished.
    ///
    /// A plain Add (no file) is ignored while another add runs, so a double tap does not create
    /// two items. Adds that carry a dropped file queue behind the running one instead: a drop of
    /// several files calls this once per file, and each must become an item.
    /// See CODE_AUDIT_Folder §3.2.
    func add(type: EditControllerAddType, url: URL?, root: any ItemRootControllable) {
        if url == nil, listModel.addItemTask != nil { return }

        let hasParent = listModel.parentModel != nil
        let targetParentId = listModel.selectedParentId
        let previous = listModel.addItemTask
        let token = UUID()
        listModel.addItemToken = token
        listModel.addItemTask = Task {
            await previous?.value
            await performAdd(type: type, url: url, root: root, hasParent: hasParent, targetParentId: targetParentId)
            if listModel.addItemToken == token {
                listModel.addItemTask = nil
                listModel.addItemToken = nil
            }
        }
    }

    private func performAdd(type: EditControllerAddType, url: URL?, root: any ItemRootControllable, hasParent: Bool, targetParentId: UUID?) async {
        guard let model = await root.editControllable.addNew(type: type) else { return }
        if let url {
            await root.editControllable.resetFile(url: url, itemId: model.id)
        }
        // The file attach above is awaited, so the item is complete here; a fixed settle
        // delay used to stand in for that. See CODE_AUDIT_Folder §3.15.
        await root.itemControllable.save()
        if hasParent {
            root.editControllable.addItem(itemId: model.id, parentId: targetParentId)
            // Reset parent list filter when adding to folder/collection
            root.folderListControllable.resetFilter()
        }
        guard let updatedModel = root.itemControllable.itemSync(for: model.id) else { return }
        listModel.addedModelId = model.id
        // Wait for the list to be rebuilt from a fresh search, so the new row exists before it
        // is selected and the editor opens over it. See CODE_AUDIT_Folder §3.15.
        await refreshAndWait()
        listModel.set(selectedItemId: updatedModel.id)
        listModel.scrollId = listModel.selected
        // File-backed modules (Audio, Pdf, Photo, Space) derive the item's name from the
        // picked file, so let the user pick a file first instead of popping the header editor.
        // Folders/collections have no file to pick, so they still open the header editor.
        let skipsHeaderEditor = type == .item && root.viewControllable.skipsHeaderEditorOnCreate
        // Only open the editor over the new item: the user may have selected another one while
        // the item was created.
        if !skipsHeaderEditor, listModel.selectedItemId == model.id {
            root.navigationModel.openHeaderEditor = true
        }

        switch type {
        case .item:
            await MasterRPGTips.donateItemCreated()
        case .folder, .collection:
            await MasterRPGTips.donateContentOrganized()
        }
        if let rootManager = root.rootManager {
            MasterRPGTips.refreshEligibility(rootManager: rootManager)
        }
    }

    /// Runs `update(debounce: false)` and returns once the list has been rebuilt. A newer
    /// refresh (the observation stream) can replace the one started here; the latest one is
    /// awaited.
    private func refreshAndWait() async {
        update(debounce: false)
        while let task = searchModel.currentTask {
            await task.value
            if searchModel.currentTask == task { break }
        }
    }
        
    @MainActor func delete(offsets: IndexSet) -> [ItemRowModel] {
        let removed = offsets.map {
            let source = listModel.list[$0].source
            return ItemRowModel(itemId: source.itemId, typeId: itemControllable.config.module)
        }
        listModel.deleteItems(offsets: offsets)
        return removed
    }
}

// Search & Filter (`resetFilter`, `buildList`, `appendToFlat`, …) lives in
// `FolderListControllable+Search.swift`; Folder Logic (`toggleFolder`, …) lives in
// `FolderListControllable+FolderLogic.swift`.
