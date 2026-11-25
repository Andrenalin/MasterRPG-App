// @copyright André Trettin

import SwiftUI
#if !os(tvOS)
import AppIntents
#endif

struct ListRowItemView: View, Equatable {
    let root: any ItemRootControllable
    let item: FolderListItemModel
    /// The folder depth, passed by value: `item` is a class instance, so comparing `item.level`
    /// in `==` compared the instance with itself and a row kept its old indent until another
    /// change (the focus) redrew it.
    let level: Int
    /// Compared in `==` so toggling selection mode redraws every row with fresh values.
    let isSelectionMode: Bool
    let listController: any FolderListControllable
    let parentModel: (any ItemDataAccessible)?
    let listModel: FolderListModel
    let menuController: ContextMenuMultiController
    let leadingPadding: CGFloat
    var focusedRowId: FocusState<UUID?>.Binding

    @State private var isDropTargeted = false
    @State private var isRangeSelectionStarted = false

    /// Indent per folder level and row insets, scaled with Dynamic Type: a fixed 16-point indent
    /// stayed small next to large text. See CODE_AUDIT_Folder §8.4.
    @ScaledMetric(relativeTo: .body) private var indentPerLevel: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var trailingInset: CGFloat = 8
    @ScaledMetric(relativeTo: .body) private var verticalInset: CGFloat = 2

    /// `root`/`listController` are existentials (capability bags, not row content) and
    /// `menuController`/`listModel`/`focusedRowId` are long-lived reference/binding
    /// dependencies passed down unchanged across parent redraws — none of those are compared.
    /// `isDropTargeted` is `@State`-owned and drives its own re-render independent of this
    /// conformance. What actually determines this row's rendered output is: which item it
    /// shows, where in the hierarchy, its content and its inset. Selection is read from the same
    /// live `listModel` on both sides, so it is not compared. See CODE_AUDIT §8.4, CODE_AUDIT_23 §8.7.
    static func == (lhs: ListRowItemView, rhs: ListRowItemView) -> Bool {
        lhs.item.id == rhs.item.id
            && lhs.level == rhs.level
            && lhs.isSelectionMode == rhs.isSelectionMode
            && lhs.leadingPadding == rhs.leadingPadding
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
            RowContentView(root: root, item: item, listController: listController, model: model, isSelected: isSelected)
                // The indent is inside the button: the focus ring then spans the whole row like
                // the selection tint, instead of starting at the indented content. In selection
                // mode it is outside the checkmark instead (below), so the circle sits on the
                // item and is indented with it.
                .padding(.leading, listController.listDisplayModel.isSelectionMode ? 0 : CGFloat(level) * indentPerLevel)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focused(focusedRowId, equals: item.id)
        .padding(.trailing, trailingInset)
        .selectListItem(
            isActive: listController.listDisplayModel.isSelectionMode,
            action: selectRow,
            isSelected: { isSelected }
        )
#if os(iOS)
        // iPhone and iPad: a touch that starts in the checkmark column selects or deselects rows
        // while it moves over them; a touch elsewhere still scrolls the list. It covers the
        // checkmark button, so a tap on it is the first step of such a gesture.
        .overlay(alignment: .leading) {
            if listController.listDisplayModel.isSelectionMode {
                Color.clear
                    .frame(width: Self.checkColumnWidth)
                    .contentShape(.rect)
                    .gesture(rangeSelectionGesture(minimumDistance: 0))
                    .accessibilityHidden(true)
            }
        }
#endif
        .padding(.leading, listController.listDisplayModel.isSelectionMode ? CGFloat(level) * indentPerLevel : 0)
        .background {
            if isDropTargeted {
                Color.accentColor.opacity(0.2)
            } else if isSelected {
                Color.accentColor.opacity(0.12)
            }
        }
        // Not in selection mode: dragging over the rows selects them there.
        .draggable(for: root.configurable.module, itemId: item.source.itemId, entryId: nil, name: model.name, isEnabled: !listController.listDisplayModel.isSelectionMode)
        .contextMenu {
            ListRootContextMenu(
                root: root,
                controller: menuController,
                parentItem: parentModel,
                currentSelected: listController.listDisplayModel.isSelectionMode ? nil : item.source.itemId,
                rowId: item.id,
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
        .padding(EdgeInsets(top: verticalInset, leading: leadingPadding, bottom: verticalInset, trailing: 0))
#if os(macOS) || os(visionOS)
        // Mouse or pinch dragging from anywhere on the row selects or deselects the rows it
        // passes over. Simultaneous, so a plain click still reaches the row's button.
        .simultaneousGesture(
            rangeSelectionGesture(minimumDistance: 4),
            isEnabled: listController.listDisplayModel.isSelectionMode
        )
#endif
#if !os(tvOS)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .listRows) } action: { frame in
            if listController.listDisplayModel.isSelectionMode {
                listModel.rowFrames[item.id] = frame
            }
        }
#endif
#if !os(tvOS)
        // Lets "open the third one" or "delete this" on the list resolve to the item. Folders are
        // entities too; only the app's own collections are not. See CODE_AUDIT_AppIntents §4.7.
        .appEntityIdentifier(entityIdentifier)
#endif
    }
}

private extension ListRowItemView {
    // Use the pre-resolved model from FolderListItemModel (set by mapResult via itemSync).
    // Falls back to itemOrEmpty only for items not yet through the search pipeline.
    var model: any ItemDataAccessible {
        item.model ?? root.itemControllable.itemOrEmpty(for: item.source.itemId)
    }

#if !os(tvOS)
    var entityIdentifier: EntityIdentifier? {
        guard item.source.entryId == nil, !model.specialCategory else { return nil }
        return IntentEntityIdentifiers.identifier(for: item.source.itemId, module: root.configurable.module)
    }
#endif

    var isSelected: Bool {
        listController.listDisplayModel.isSelectionMode
            ? listModel.listSelection.contains(item.id)
            : listModel.selected == item.id
    }

    func selectRow() {
        focusedRowId.wrappedValue = item.id
        listModel.keyboardRowId = item.id
        listModel.endRangeSelection()
        if listController.listDisplayModel.isSelectionMode {
            listModel.toggleListSelection(of: item.id)
        } else {
            listModel.selected = item.id
        }
    }

    /// The checkmark button with its padding.
    static var checkColumnWidth: CGFloat { 60 }

#if !os(tvOS)
    /// Selection mode: the row where the gesture starts decides whether it selects or deselects
    /// (an unselected row selects, a selected one deselects); every row between there and the
    /// pointer then follows. Moving back shrinks the range again.
    func rangeSelectionGesture(minimumDistance: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: minimumDistance, coordinateSpace: .listRows)
            .onChanged { value in
                if !isRangeSelectionStarted {
                    isRangeSelectionStarted = true
                    focusedRowId.wrappedValue = item.id
                    listModel.keyboardRowId = item.id
                    listModel.endRangeSelection()
                    listModel.beginRangeSelection(at: item.id)
                }
                if let rowId = listModel.rowId(atY: value.location.y) {
                    listModel.extendRangeSelection(to: rowId)
                    listModel.keyboardRowId = rowId
                }
            }
            .onEnded { _ in
                isRangeSelectionStarted = false
                listModel.endRangeSelection()
            }
    }
#endif

    /// Reordering (via drag) is only meaningful for a collection's own children list —
    /// mirrors the previous `List` `.moveDisabled(parentModel == nil || parentModel?.category == .folder)`.
    var canReorder: Bool {
        guard let parentModel else { return false }
        return parentModel.category != .folder
    }

    /// Distinguishes "drop this sibling row to reorder" from "drop an external item to add it
    /// here" purely by list membership — reuses the same `draggable`/`dropDestination` pair for
    /// both, the same approach used by `SheetView`/`SheetEntryView` for entry reordering.
    /// Reorders by row id, not list position: the list can be filtered, skip trashed members
    /// or show nested rows, so its positions are not positions in the parent's entries.
    /// See CODE_AUDIT_Folder §5.15.
    func handleDrop(name: String, itemId: UUID, entryId: UUID?) {
        guard let parentModel else { return }
        if let sourceRow = listModel.list.first(where: { $0.source.itemId == itemId && $0.level == 0 }),
           let sourceRowId = sourceRow.source.entryId,
           let targetRowId = item.source.entryId,
           sourceRow.id != item.id {
            withAnimation {
                root.editControllable.moveMember(rowId: sourceRowId, to: targetRowId, in: parentModel.id)
            }
        } else {
            addLink(name: name, itemId: itemId, entryId: entryId)
        }
    }

    func addLink(name: String, itemId: UUID, entryId: UUID?) {
        guard let parentModel else { return }
        addDroppedMember(itemId: itemId, to: parentModel.id, root: root, listController: listController)
    }
}

private struct RowContentView: View {
    let root: any ItemRootControllable
    let item: FolderListItemModel
    let listController: any FolderListControllable
    let model: any ItemDataAccessible
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center) {
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
            .equatable()

            SpecialCategoryFolderIndicator(
                item: item,
                listController: listController
            )
        }
        .environment(listController.listDisplayModel)
    }
}

#Preview {
    @Previewable @FocusState var focusedRowId: UUID?
    let fixture = FakeItemRootControllerFixture()
    let item = {
        let item = FolderListItemModel(
            id: .fixture1,
            source: ItemRowModel(itemId: .fixture2, typeId: .none),
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
        level: item.level,
        isSelectionMode: false,
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
