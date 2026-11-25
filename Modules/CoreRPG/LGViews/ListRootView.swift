// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main View

struct ListRootView: View {
    let root: any ItemRootControllable
    let listController: any FolderListControllable
    let parentModel: (any ItemDataAccessible)?
    var isSubFolder: Bool
    
    @Environment(\.navigator) private var navigator
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(AppFocusModel.self) private var appFocusModel

    @State private var scrollPosition = ScrollPosition(idType: UUID.self)
    @State private var generationSelection: WindowItemSelection?
    
    /// Per-row focus target — not a container-level bool. A single `.focusable()` on the
    /// `ScrollView` would compete with each row's own `Button` for the click, since the
    /// container and the row are two separate focusable targets (see swift-focusengine-pro
    /// anti-pattern #25/#3): the container can win the click and just take focus instead of
    /// activating the row's button, silently breaking tap-to-select.
    @FocusState private var focusedRowId: UUID?

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        UnavailableGlassOverlay(isUnavailable: shouldShowNoResults
                                && !listController.searchModel.searchText.starts(with: "@")) {
            
            ListView(
                root: root,
                listController: listController,
                parentModel: parentModel,
                listModel: listModel,
                menuController: menuController,
                focusedRowId: $focusedRowId,
                scrollPosition: $scrollPosition
            )
                .animation(accessibilityReduceMotion ? nil : .smooth, value: listModel.list.count)
                .frame(minWidth: 200, idealWidth: 350)
                .scrollIndicatorsFlash(onAppear: true)
                .scrollIndicatorsFlash(trigger: listModel.list.count)
#if !os(visionOS)
                .scrollDismissesKeyboard(.immediately)
#endif
#if os(macOS)
                .onDeleteCommand {
                    guard let sel = listModel.selected,
                          let index = listModel.list.firstIndex(where: { $0.id == sel }) else { return }
                    deleteItems(offsets: IndexSet(integer: index))
                }
#endif
#if !os(tvOS)
                .onKeyPress(.upArrow, phases: .down) { _ in moveSelection(by: -1) }
                .onKeyPress(.downArrow, phases: .down) { _ in moveSelection(by: 1) }
                .onKeyPress(.space, phases: [.down, .repeat, .up]) { keyPress in
                    guard keyPress.modifiers.isEmpty else { return .ignored }
                    if listController.listDisplayModel.isSelectionMode {
                        return toggleKeyboardRowFolder(phase: keyPress.phase)
                    }
                    guard keyPress.phase == .down,
                          listController.canToggleFolder(itemId: listModel.selectedItemId) else {
                        return .ignored
                    }
                    withAnimation(accessibilityReduceMotion ? nil : .default) {
                        _ = listController.toggleSelectedFolder()
                    }
                    return .handled
                }
                .onKeyPress(.return, phases: .down) { keyPress in
                    guard keyPress.modifiers.isEmpty else { return .ignored }
                    if listController.listDisplayModel.isSelectionMode {
                        return toggleFocusedRowSelection(phase: keyPress.phase)
                    }
                    guard ItemPrimaryAction.canPerform(root: root) else { return .ignored }
                    ItemPrimaryAction.perform(root: root, scenesManager: scenesManager)
                    return .handled
                }
                .onKeyPress(.escape, phases: .down) { keyPress in
                    guard keyPress.modifiers.isEmpty,
                          listController.listDisplayModel.isSelectionMode else { return .ignored }
                    withAnimation(accessibilityReduceMotion ? nil : .default) {
                        listController.listDisplayModel.isSelectionMode = false
                    }
                    return .handled
                }
                .onKeyPress(.leftArrow, phases: .down) { _ in
                    appFocusModel.navigationColumnFocus = .tabs
                    return .handled
                }
                .onKeyPress(.rightArrow, phases: .down) { _ in
                    if listController.canOpenFolder(itemId: listModel.selected) {
                        withAnimation(accessibilityReduceMotion ? nil : .default) { listController.openSelectedFolder() }
                    } else if let sheetRootModel = root.editControllable.editorModel.sheetRootModel,
                              sheetRootModel.sheetModel.source.itemId == listModel.selectedItemId {
                        // Selecting the first entry when nothing is selected yet, and focusing
                        // whichever entry ends up selected, is `SheetRootView`'s job — it owns
                        // that decision so re-entering a sheet keeps an existing selection
                        // instead of always resetting to the first entry.
                        appFocusModel.navigationColumnFocus = .detail
                    }
                    return .handled
                }
#endif
        }
        .listModelUpdatesModifier(listControllable: listController, itemControllable: root.itemControllable, parentModel: parentModel)
        .applyIf(!isSubFolder) {
            $0.toolbarItemListModifier(root: root, listControllable: listController, parentModel: parentModel)
        }
#if !os(tvOS)
        .applyIf(!fileTypes.isEmpty) {
            $0.onDrop(of: [.fileURL], delegate: FileDropDelegate(for: fileTypes, updateFile: updateFile))
        }
#endif
        .applyIf(parentModel == nil) {
            $0
                .navigationTitle(
                    Text("\(root.configurable.module.title) - \(listModel.list.count)", bundle: .module)
                )
                .focusedSceneValue(\.listDisplayModel, listController.listDisplayModel)
                .onChange(of: root.navigationModel.triggerExport) {
                    guard root.navigationModel.triggerExport, let itemId = root.currentSelectedItemId else { return }
                    root.navigationModel.triggerExport = false
                    navigator.navigate(to: InternalRoute.export(ids: [itemId]), method: .sheet)
                }
                .onChange(of: root.navigationModel.triggerGroupEditor) {
                    guard root.navigationModel.triggerGroupEditor, let itemId = root.currentSelectedItemId else { return }
                    root.navigationModel.triggerGroupEditor = false
                    navigator.navigate(to: InternalRoute.groupEditor(ids: [itemId]), method: .sheet)
                }
                .onChange(of: root.navigationModel.triggerBatchExtraction) {
                    guard root.navigationModel.triggerBatchExtraction, let itemId = root.currentSelectedItemId else { return }
                    root.navigationModel.triggerBatchExtraction = false
                    navigator.navigate(to: InternalRoute.batchExtraction(ids: [itemId]), method: .sheet)
                }
                .onChange(of: root.navigationModel.triggerCloudScan) {
                    guard root.navigationModel.triggerCloudScan else { return }
                    root.navigationModel.triggerCloudScan = false
                    guard !root.itemControllable.itemDataModel.isGameMode else { return }
                    navigator.navigate(to: InternalRoute.cloudFolderScan, method: .sheet)
                }
                .onChange(of: root.navigationModel.triggerDelete) {
                    guard root.navigationModel.triggerDelete else { return }
                    root.navigationModel.triggerDelete = false
                    guard let sel = listModel.selected,
                          let index = listModel.list.firstIndex(where: { $0.id == sel }) else { return }
                    deleteItems(offsets: IndexSet(integer: index))
                }
                .onChange(of: root.navigationModel.triggerSpaceAction) {
                    guard root.navigationModel.triggerSpaceAction else { return }
                    root.navigationModel.triggerSpaceAction = false
                    guard !root.viewControllable.hasCustomSpaceAction,
                          root.openFileWindowModel.enabled else { return }
                    withAnimation(accessibilityReduceMotion ? nil : .default) { root.openFileWindowModel.showItem.toggle() }
                }
        }
        .itemGenerationPresentation(
            root: root,
            selection: $generationSelection
        )
        .generateFromPhotoPresentation(root: root)
    }
}

// MARK: - ListRootView private helpers

private extension ListRootView {
    /// When the view is showing a folder/collection's children (`parentModel != nil`),
    /// route all list operations through `detailListModel` so the detail list is
    /// displayed and mutated — not the root list.
    var listModel: FolderListModel {
        listController.scopedListModel(parentModel: parentModel)
    }

    /// Determines if the "no results" overlay should be shown.
    var shouldShowNoResults: Bool {
        listController.shouldShowNoResults
    }
    
    var fileTypes: [UTType] {
        root.editControllable.fileUrlDataController?.fileTypes ?? []
    }
    
    /// Computed once per body evaluation and passed down — avoids per-row re-creation.
    var menuController: ContextMenuMultiController {
        ContextMenuMultiController(editController: root.editControllable, itemController: root.itemControllable, listModel: listModel)
    }
    
    func updateFile(url: URL) {
        listController.add(type: .item, url: url, root: root, parentId: parentModel?.id)
    }

    /// Replaces the row-to-row up/down arrow navigation `List` gave for free. In selection mode the
    /// arrows only move the keyboard focus (the ring) to the previous / next row, so a
    /// multi-selection is never collapsed; Space then toggles the focused row.
    func moveSelection(by offset: Int) -> KeyPress.Result {
        let isSelectionMode = listController.listDisplayModel.isSelectionMode
        let current = isSelectionMode ? keyboardRow : listModel.selected
        guard let target = listModel.rowId(offsetBy: offset, from: current) else { return .ignored }
        if !isSelectionMode {
            listModel.selected = target
        }
        listModel.keyboardRowId = target
        listModel.scrollId = target
        listModel.recordVisibleScrollPosition(target)
        focusedRowId = target
        withAnimation(accessibilityReduceMotion ? nil : .default) {
            scrollPosition = ScrollPosition(id: target)
        }
        return .handled
    }

    /// The row the keyboard acts on in selection mode: the focused row, else the last row
    /// clicked or moved to.
    var keyboardRow: UUID? {
        focusedRowId ?? listModel.keyboardRowId
    }

    /// Return in selection mode: selects / deselects the keyboard row.
    func toggleFocusedRowSelection(phase: KeyPress.Phases) -> KeyPress.Result {
        guard listController.listDisplayModel.isSelectionMode,
              let rowId = keyboardRow,
              listModel.list.contains(where: { $0.id == rowId }) else { return .ignored }
        if phase == .down {
            listModel.toggleListSelection(of: rowId)
        }
        return .handled
    }

    /// Space in selection mode: opens / closes the keyboard row when it is a folder. Only the
    /// key-down acts; repeats and the key-up are consumed, so the focused row button cannot
    /// also select the row by its own activation.
    func toggleKeyboardRowFolder(phase: KeyPress.Phases) -> KeyPress.Result {
        guard let rowId = keyboardRow,
              listModel.list.contains(where: { $0.id == rowId }) else { return .ignored }
        if phase == .down, listController.canToggleFolder(itemId: rowId) {
            withAnimation(accessibilityReduceMotion ? nil : .default) {
                _ = listController.toggleFolder(itemId: rowId)
            }
        }
        return .handled
    }

    /// Used by `onDeleteCommand` (macOS) and the `triggerDelete` onChange handler.
    func deleteItems(offsets: IndexSet) {
        if let parentModel {
            // By row id: list positions are not positions in the parent's entries.
            // See CODE_AUDIT_Folder §5.15.
            let rowIds = Set(offsets.compactMap { listModel.list.indices.contains($0) ? listModel.list[$0].source.entryId : nil })
            root.editControllable.removeMembers(rowIds: rowIds, from: parentModel.id)
            listModel.deleteItems(offsets: offsets)
        } else {
            let removingItems = listController.delete(offsets: offsets)
            guard !removingItems.isEmpty else { return }
            root.removeEntryListModel.present(root.editControllable.collectionItemsForRemoval(for: removingItems))
            navigator.navigate(to: InternalRoute.removeAlert, method: .managedSheet)
        }
    }
}

// MARK: - Added row reveal

private extension View {
    func revealAddedRow(in listModel: FolderListModel, scrollPosition: Binding<ScrollPosition>) -> some View {
        modifier(RevealAddedRowModifier(listModel: listModel, scrollPosition: scrollPosition))
    }
}

/// A newly added entry/group becomes selected — reveal it once its row exists. `addedModelId` is
/// set before the list is rebuilt, so the reveal waits for the rebuilt list.
private struct RevealAddedRowModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let listModel: FolderListModel
    @Binding var scrollPosition: ScrollPosition

    /// The item added last, until its row exists in the list and has been revealed.
    @State private var pendingRevealItemId: UUID?

    func body(content: Content) -> some View {
        content
            .onChange(of: listModel.addedModelId) {
                guard let addedId = listModel.addedModelId else { return }
                pendingRevealItemId = addedId
                revealPendingRow()
            }
            // The ids are only tracked while a reveal waits for its row.
            // See CODE_AUDIT_23 §7.15.
            .onChange(of: pendingRevealItemId == nil ? [] : listModel.list.map(\.id)) {
                revealPendingRow()
            }
    }

    /// Scrolls just far enough to show the added row, then releases the tracked position. A
    /// `ScrollPosition(id:anchor:)` is not one-shot: it keeps re-applying itself whenever the
    /// list is resized (the header editor and its keyboard do that right after an add), which
    /// could leave the new row, the first one as it has no name yet, under the navigation bar.
    private func revealPendingRow() {
        guard let itemId = pendingRevealItemId else { return }
        guard let row = listModel.row(itemId: itemId) else {
            // The add is over and the row is not in this list (filtered out): nothing to reveal.
            if listModel.addedModelId == nil { pendingRevealItemId = nil }
            return
        }
        pendingRevealItemId = nil
        withAnimation(accessibilityReduceMotion ? nil : .default, completionCriteria: .logicallyComplete) {
            scrollPosition.scrollTo(id: row.id)
        } completion: {
            scrollPosition = ScrollPosition(idType: UUID.self)
        }
    }
}

// MARK: - List content

private struct ListView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(AppFocusModel.self) private var appFocusModel

    let root: any ItemRootControllable
    let listController: any FolderListControllable
    let parentModel: (any ItemDataAccessible)?
    let listModel: FolderListModel
    let menuController: ContextMenuMultiController
    var focusedRowId: FocusState<UUID?>.Binding

    @Binding var scrollPosition: ScrollPosition

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                ItemRowsView(root: root, listController: listController, parentModel: parentModel, listModel: listModel, menuController: menuController, focusedRowId: focusedRowId)
            }
            .frame(maxWidth: .infinity)
            .scrollTargetLayout()
        }
#if os(macOS)
        .applyIf(parentModel != nil) {
            $0.frame(minHeight: 300, maxHeight: .infinity)
        }
#endif
        .scrollPosition($scrollPosition)
        // Always record where the list is actually scrolled to, regardless of what moved it —
        // this is the persisted "come back to where you left off" state. Skipped while a search
        // is active so `lastNonNilScrollId` keeps remembering the pre-search browsing position
        // instead of wherever the filtered results happen to be scrolled to.
        .onChange(of: scrollPosition) {
            guard let id = scrollPosition.viewID(type: UUID.self), listModel.scrollId != id else { return }
            listModel.scrollId = id
            if listController.searchModel.searchText.isEmpty {
                listModel.recordVisibleScrollPosition(id)
            }
        }
        // Generic follow for scrollId writes from elsewhere (keyboard column-focus switch,
        // post-search restoration) — minimal-disruption `.top` anchor. Backs off while a new
        // item is being added so the dedicated `addedModelId` handler below (`revealPendingRow`)
        // owns that scroll instead.
        .onChange(of: listModel.scrollId) {
            guard listModel.addedModelId == nil,
                  let id = listModel.scrollId,
                  scrollPosition.viewID(type: UUID.self) != id else { return }
            scrollPosition = ScrollPosition(id: id, anchor: .top)
        }
        .revealAddedRow(in: listModel, scrollPosition: $scrollPosition)
        // Starting a search shows the current selection at the top; clearing it returns to
        // wherever the list was scrolled to before the search began.
        .onChange(of: listController.searchModel.searchText) { oldValue, newValue in
            if oldValue.isEmpty, !newValue.isEmpty, let selected = listModel.selected {
                withAnimation(accessibilityReduceMotion ? nil : .default) {
                    scrollPosition = ScrollPosition(id: selected, anchor: .top)
                }
            } else if !oldValue.isEmpty, newValue.isEmpty, let restoreId = listModel.lastNonNilScrollId {
                withAnimation(accessibilityReduceMotion ? nil : .default) {
                    scrollPosition = ScrollPosition(id: restoreId, anchor: .top)
                }
            }
        }
        .task {
            // Snapshot the exact recorded position (not just whether one exists) before
            // `applyPostUpdateSelection` runs below — it can itself derive a fresh `scrollId`,
            // which would silently move the restore target away from where the list actually
            // was before this appearance. Applies on every platform: switching away to another
            // module and back can recreate this view (fresh `@State`), so the scroll offset
            // isn't always preserved for free.
            let recordedScrollId = listModel.scrollId
            // The item id, not the row id, and the live generation: a literal 0 made the
            // restore a no-op after the first navigation reset. See CODE_AUDIT_Folder §5.30.
            let initialSelectedItemId = listModel.selectedItemId
            let selectionGeneration = listModel.selectionGeneration
            await Task.yield()
            guard !Task.isCancelled else { return }
            if let initialSelectedItemId {
                listController.applyPostUpdateSelection(previousSelectedId: initialSelectedItemId, selectionGeneration: selectionGeneration)
            }
            if let recordedScrollId {
                scrollPosition = ScrollPosition(id: recordedScrollId, anchor: .top)
            } else if let selected = listModel.selected {
                // First-ever appearance with a selection restored from persisted state
                // (no scroll memory yet) — reveal it centered.
                scrollPosition = ScrollPosition(id: selected, anchor: .center)
            }
        }
        .focusedValue(\.moduleListIsFocused, true)
        .accessibilityIdentifier("module.list.\(root.configurable.module.token)")
        .themedListSurface()
        .onChange(of: appFocusModel.navigationColumnFocus) {
            guard appFocusModel.navigationColumnFocus == .list else { return }
            focusPreferredListRow()
        }
    }

    private func focusPreferredListRow() {
        let target = listModel.selected.flatMap { selected in
            listModel.list.first(where: { $0.id == selected })?.id
        } ?? listModel.list.first?.id
        guard let target else { return }
        listModel.selected = target
        listModel.listSelection = [target]
        listModel.scrollId = target
        listModel.recordVisibleScrollPosition(target)
        // Deferred: the target row's Button may not exist in the LazyVStack's hierarchy yet
        // (offscreen, not yet laid out from the scroll this same call just triggered) —
        // assigning @FocusState synchronously in that case is silently dropped. One runloop
        // tick gives the scroll and layout time to settle first.
        Task { @MainActor in
            focusedRowId.wrappedValue = target
        }
    }
}

#Preview("Item List") {
    let fixture = FakeItemRootControllerFixture()
    ListRootView(root: fixture.root, listController: fixture.folderListController, parentModel: nil, isSubFolder: false)
        .environment(AppFocusModel())
}
