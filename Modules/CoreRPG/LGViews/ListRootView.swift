// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main View

struct ListRootView: View {
    let root: ItemRootControllable
    let listController: any FolderListControllable
    let parentModel: (any ItemDataAccessable)?
    var isSubFolder: Bool
    
    @Environment(\.navigator) private var navigator
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.switchToDetailColumn) private var switchToDetailColumn
    @Environment(\.navigationColumnFocus) private var navigationColumnFocus
    @Environment(ScenesManager.self) private var scenesManager

    @State private var userScrollIsActive = false
    @State private var generationSelection: WindowItemSelection?
    
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        UnavailableGlassOverlay(isUnavailable: shouldShowNoResults
                                && !listController.searchModel.searchText.starts(with: "@")) {
            
            listView
                .animation(accessibilityReduceMotion ? nil : .smooth, value: listModel.list.count)
                .frame(minWidth: 250, idealWidth: 350)
#if !os(tvOS)
            // Always-present modifier: empty closure = no menu; avoids applyIf identity break
                .contextMenu(forSelectionType: FolderListItemModel.ID.self) { _ in
                    if listController.listDisplayModel.isSelectionMode {
                        ListRootContextMenu(root: root, controller: menuController, parentItem: parentModel, listController: listController)
                    }
                }
#endif
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
                .onKeyPress(.space, phases: .down) { keyPress in
                    guard keyPress.modifiers.isEmpty,
                          listController.canToggleFolder(itemId: listModel.selectedItemId) else {
                        return .ignored
                    }
                    withAnimation(accessibilityReduceMotion ? nil : .default) {
                        _ = listController.toggleSelectedFolder()
                    }
                    return .handled
                }
                .onKeyPress(.return, phases: .down) { keyPress in
                    guard keyPress.modifiers.isEmpty,
                          ItemPrimaryAction.canPerform(root: root) else {
                        return .ignored
                    }
                    ItemPrimaryAction.perform(root: root, scenesManager: scenesManager)
                    return .handled
                }
                .onKeyPress(.leftArrow, phases: .down) { _ in
                    navigationColumnFocus?.wrappedValue = .tabs
                    return .handled
                }
                .onKeyPress(.rightArrow, phases: .down) { _ in
                    if listController.canOpenFolder(itemId: listModel.selected) {
                        withAnimation(accessibilityReduceMotion ? nil : .default) { listController.openSelectedFolder() }
                    } else if let sheetRootModel = root.editControllable.editorModel.sheetRootModel,
                              sheetRootModel.sheetModel.source.itemId == listModel.selectedItemId,
                              let firstEntry = sheetRootModel.firstSelectableEntry {
                        sheetRootModel.setSelected(firstEntry, parent: sheetRootModel.sheetModel)
                        navigationColumnFocus?.wrappedValue = .detail
                        switchToDetailColumn()
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
    }
}

// MARK: - ListRootView private helpers

private extension ListRootView {
    /// When the view is showing a folder/collection's children (`parentModel != nil`),
    /// route all list operations through `detailListModel` so the detail list is
    /// displayed and mutated — not the root list.
    var listModel: FolderListModel {
        if parentModel != nil, let detail = listController.listModel.detailListModel {
            return detail
        }
        return listController.listModel
    }
    
    /// Determines if the "no results" overlay should be shown.
    ///
    /// Uses `searchModel.searchReturnedNoResults` rather than `listModel.list.isEmpty`: `buildList`
    /// deliberately preserves the previous list when a search returns nothing (anti-flicker), so
    /// `list.isEmpty` is never true even when the search matched zero items. The flag is set by the
    /// single search pipeline, so it always reflects the active (and only) in-flight search.
    var shouldShowNoResults: Bool {
        listController.searchModel.searchReturnedNoResults
    }
    
    var fileTypes: [UTType] {
        root.editControllable.fileUrlDataController?.fileTypes ?? []
    }
    
    /// Computed once per body evaluation and passed down — avoids per-row re-creation.
    var menuController: ContextMenuMultiController {
        ContextMenuMultiController(editController: root.editControllable, itemController: root.itemControllable, listModel: listModel)
    }
    
    func updateFile(url: URL) {
        listController.add(type: .item, url: url, root: root)
    }
    
    @ViewBuilder
    var listView: some View {
        @Bindable var listModel = listModel
        Group {
#if os(macOS)
            Group {
                if listController.listDisplayModel.isSelectionMode {
                    List(selection: $listModel.listSelection) {
                        ItemRowsView(root: root, listController: listController, parentModel: parentModel, listModel: listModel, menuController: menuController)
                    }
                    .frame(minHeight: 300, maxHeight: .infinity)
                } else {
                    List(selection: $listModel.selected) {
                        ItemRowsView(root: root, listController: listController, parentModel: parentModel, listModel: listModel, menuController: menuController)
                    }
                    .frame(minHeight: 300, maxHeight: .infinity)
                }
            }
            .applyIf(parentModel != nil) {
                $0.listStyle(.bordered)
            }
#else
            List(selection: $listModel.listSelection) {
                ItemRowsView(root: root, listController: listController, parentModel: parentModel, listModel: listModel, menuController: menuController)
            }
#endif
        }
        .scrollPosition(id: $listModel.scrollId, anchor: .center)
        .navigationColumnFocused(navigationColumnFocus, equals: .list)
        .focusedValue(\.moduleListIsFocused, true)
        .accessibilityIdentifier("module.list.\(root.configurable.module.token)")
        .themedListSurface()
        .onChange(of: navigationColumnFocus?.wrappedValue) { _, newValue in
            guard newValue == .list else { return }
            focusPreferredListRow()
        }
#if os(macOS)
        .onScrollPhaseChange { _, newPhase in
            switch newPhase {
            case .tracking, .interacting, .decelerating:
                userScrollIsActive = true
            case .idle:
                if userScrollIsActive {
                    listModel.recordVisibleScrollPosition(listModel.scrollId)
                }
                userScrollIsActive = false
            case .animating:
                break
            }
        }
        .onAppear {
            restoreMacScrollPosition()
        }
        .onDisappear {
            if userScrollIsActive {
                listModel.recordVisibleScrollPosition(listModel.scrollId)
            }
            userScrollIsActive = false
        }
        .onChange(of: listModel.list.map(\.id)) {
            restoreMacScrollPosition()
        }
#endif
    }

#if os(macOS)
    func restoreMacScrollPosition() {
        listModel.scrollId = listModel.restoredScrollTarget(
            selection: listModel.selected
        )
    }
#endif

    func focusPreferredListRow() {
        let target = listModel.selected.flatMap { selected in
            listModel.list.first(where: { $0.id == selected })?.id
        } ?? listModel.list.first?.id
        guard let target else { return }
        listModel.selected = target
        listModel.listSelection = [target]
        listModel.scrollId = target
        listModel.recordVisibleScrollPosition(target)
    }
    
    /// Used by `onDeleteCommand` (macOS) and the `triggerDelete` onChange handler.
    func deleteItems(offsets: IndexSet) {
        if let parentModel {
            root.editControllable.removeItem(offsets: offsets, itemId: parentModel.id)
            listModel.deleteItems(offsets: offsets)
        } else {
            let removingItems = listController.delete(offsets: offsets)
            guard !removingItems.isEmpty else { return }
            root.removeEntryListModel.removeItems = root.editControllable.markCollectionItemsForRemoval(for: removingItems)
            navigator.navigate(to: InternalRoute.removeAlert, method: .managedSheet)
        }
    }
}

#Preview("Item List") {
    let fixture = FakeItemRootControllerFixture()
    ListRootView(root: fixture.root, listController: fixture.folderListController, parentModel: nil, isSubFolder: false)
}
