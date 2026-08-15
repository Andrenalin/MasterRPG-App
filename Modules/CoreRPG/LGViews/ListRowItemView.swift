// @copyright André Trettin

import SwiftUI

struct ListRowItemView: View, Equatable {
    let root: any ItemRootControllable
    let item: FolderListItemModel
    let listController: any FolderListControllable
    let parentModel: (any ItemDataAccessable)?
    let listModel: FolderListModel
    let menuController: ContextMenuMultiController
    let leadingPadding: CGFloat
    var focusedRowId: FocusState<UUID?>.Binding

    @State private var isDropTargeted = false

    /// `root`/`listController` are existentials (capability bags, not row content) and
    /// `menuController`/`listModel`/`focusedRowId` are long-lived reference/binding
    /// dependencies passed down unchanged across parent redraws — none of those are compared.
    /// `isDropTargeted` is `@State`-owned and drives its own re-render independent of this
    /// conformance. What actually determines this row's rendered output is: which item it
    /// shows, where in the hierarchy, its content, and whether it's selected. See CODE_AUDIT §8.4.
    static func == (lhs: ListRowItemView, rhs: ListRowItemView) -> Bool {
        lhs.item.id == rhs.item.id
            && lhs.item.level == rhs.item.level
            && lhs.isSelected == rhs.isSelected
            && lhs.model.isEqualErased(to: rhs.model)
    }

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        // The row's tap target is a `Button` wrapping the content directly (not an invisible
        // `.background()` button behind it). A background button never reliably received taps
        // in this ScrollView/LazyVStack context — confirmed live on-device with a debugger
        // breakpoint on selectRow() that never hit on tap, across several modifier orderings.
        // A foreground-wrapping Button is the standard, reliable SwiftUI list-row pattern; the
        // trailing folder chevron nested inside still receives its own taps independently
        // because `.buttonStyle(.plain)` lets the innermost tapped control win.
        Button(action: selectRow) {
            rowContent
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focused(focusedRowId, equals: item.id)
        .padding(.trailing, 8)
        .padding(.leading, CGFloat(item.level * 16))
        .selectListItem(
            isActive: listController.listDisplayModel.isSelectionMode,
            action: selectRow,
            isSelected: { isSelected }
        )
        .background {
            if isDropTargeted {
                Color.accentColor.opacity(0.2)
            } else if isSelected {
                Color.accentColor.opacity(0.12)
            }
        }
        .draggable(for: root.configurable.module, itemId: item.source.itemId, entryId: nil, name: model.name)
        .contextMenu {
            ListRootContextMenu(
                root: root,
                controller: menuController,
                parentItem: parentModel,
                currentSelected: listController.listDisplayModel.isSelectionMode ? nil : item.source.itemId,
                listController: listController
            )
        }
        .applyIf(canReorder) {
            $0.dropDestination(for: root.configurable.module, handler: handleDrop) { isTargeted in
                isDropTargeted = isTargeted
            }
        }
        .applyIf(!canReorder && parentModel != nil) {
            $0.dropDestination(for: root.configurable.module, isEnabled: true, handler: addLink)
        }
        .padding(EdgeInsets(top: 2, leading: leadingPadding, bottom: 2, trailing: 0))
    }
}

private extension ListRowItemView {
    // Use the pre-resolved model from FolderListItemModel (set by mapResult via itemSync).
    // Falls back to itemOrEmpty only for items not yet through the search pipeline.
    var model: any ItemDataAccessable {
        item.model ?? root.itemControllable.itemOrEmpty(for: item.source.itemId)
    }

    var rowContent: some View {
        HStack(alignment: .bottom) {
            ItemRowView(
                root: root,
                model: model,
                cacheItemListModel: listController.cacheListItemModel,
                listDisplayModel: listController.listDisplayModel,
                searchModel: listController.searchModel,
                isSelected: isSelected
            ) {
                if root.viewControllable.thumbnailRowViewType == .custom {
                    root.viewControllable.thumbnailRowView(for: item.source.itemId)
                } else if root.viewControllable.thumbnailRowViewType == .photo,
                          let cacheController = root.cacheControllable {
                    ThumbnailRowPhotoView(
                        cacheController: cacheController,
                        model: model,
                        listDisplayModel: listController.listDisplayModel
                    )
                }
            }

            SpecialCategoryFolderIndicator(
                item: item,
                listController: listController
            )
        }
        .environment(listController.listDisplayModel)
    }

    var isSelected: Bool {
        listController.listDisplayModel.isSelectionMode
            ? listModel.listSelection.contains(item.id)
            : listModel.selected == item.id
    }

    func selectRow() {
        focusedRowId.wrappedValue = item.id
        if listController.listDisplayModel.isSelectionMode {
            if listModel.listSelection.contains(item.id) {
                listModel.listSelection.remove(item.id)
            } else {
                listModel.listSelection.insert(item.id)
            }
        } else {
            listModel.selected = item.id
        }
    }

    /// Reordering (via drag) is only meaningful for a collection's own children list —
    /// mirrors the previous `List` `.moveDisabled(parentModel == nil || parentModel?.category == .folder)`.
    var canReorder: Bool {
        guard let parentModel else { return false }
        return parentModel.category != .folder
    }

    /// Distinguishes "drop this sibling row to reorder" from "drop an external item to add it
    /// here" purely by list membership — reuses the same `draggable`/`dropDestination` pair for
    /// both, the same approach used by `SheetView`/`SheetEntryView` for entry reordering.
    func handleDrop(name: String, itemId: UUID, entryId: UUID?) {
        guard let parentModel else { return }
        if let sourceIndex = listModel.list.firstIndex(where: { $0.source.itemId == itemId }),
           let targetIndex = listModel.list.firstIndex(where: { $0.id == item.id }),
           sourceIndex != targetIndex {
            withAnimation {
                let destination = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
                root.editControllable.moveItems(source: IndexSet(integer: sourceIndex), destination: destination, itemId: parentModel.id)
            }
        } else {
            addLink(name: name, itemId: itemId, entryId: entryId)
        }
    }

    func addLink(name: String, itemId: UUID, entryId: UUID?) {
        guard let parentModel else { return }
        withAnimation {
            root.editControllable.addItem(itemId: itemId, parentId: parentModel.id)
            listController.scheduleDetailSearch()
            root.folderListControllable.resetFilter()
            Task {
                await MasterRPGTips.donateContentOrganized()
            }
        }
    }
}

#Preview {
    @Previewable @FocusState var focusedRowId: UUID?
    let fixture = FakeItemRootControllerFixture()
    let item = {
        let item = FolderListItemModel(
            id: .fixture1,
            source: ItemRowModel(itemId: .fixture2, typeId: .none),
            destination: nil,
            level: 0,
            isShown: false
        )
        item.model = FakeItemModel(
            id: .fixture2,
            name: "Goblin Ambush",
            description: "A deterministic list row.",
            entries: []
        )
        return item
    }()
    ListRowItemView(
        root: fixture.root,
        item: item,
        listController: fixture.folderListController,
        parentModel: nil,
        listModel: fixture.folderListController.listModel,
        menuController: ContextMenuMultiController(
            editController: fixture.editController,
            itemController: fixture.itemController,
            listModel: fixture.folderListController.listModel
        ),
        leadingPadding: 8,
        focusedRowId: $focusedRowId
    )
    .environment(AppGameStateModel())
    .environment(\.locale, .init(identifier: "de"))
}
