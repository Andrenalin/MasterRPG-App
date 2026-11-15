// @copyright André Trettin

import SwiftUI

struct ListRootContextMenu: View {
    init(root: any ItemRootControllable, controller: ContextMenuMultiController, parentItem: (any ItemDataAccessible)?, currentSelected: UUID? = nil, listController: (any FolderListControllable)? = nil) {
        self.root = root
        self.controller = controller
        self.parentItem = parentItem
        self.currentSelected = currentSelected
        self.listController = listController
    }

    let root: any ItemRootControllable
    let controller: ContextMenuMultiController
    let parentItem: (any ItemDataAccessible)?
    let currentSelected: UUID?
    let listController: (any FolderListControllable)?

    @Environment(\.navigator) private var navigator
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.itemGenerationAction) private var itemGenerationAction
    
    var body: some View {
        let parent = self.parent
        EditItemView(root: root, title: title)
        DuplicateItemView(controller: controller, currentSelected: currentSelected, title: title)
        if !listDisplayModel.isListMode {
            Divider()
            FolderPlacementMenu(isFolder: false, controller: controller, currentSelected: currentSelected, listController: listController)
                #if !os(tvOS)
                .keyboardShortcut("a", modifiers: [.command, .shift])
                #endif
            FolderPlacementMenu(isFolder: true, controller: controller, currentSelected: currentSelected, listController: listController)
        }
        RemoveFromParentActions(
            root: root,
            controller: controller,
            listController: listController,
            currentSelected: currentSelected,
            parent: parent,
            title: title
        )
        Divider()
        OpenFolderButton(listController: listController, itemId: currentSelected, title: title)
        CloseFolderButton(listController: listController, itemId: currentSelected)
        Divider()
        ExportItemView(controller: controller, currentSelected: currentSelected, title: title)
        GroupEditView(controller: controller, currentSelected: currentSelected, title: title)
        MoveIntoGroupMenu(root: root, controller: controller, currentSelected: currentSelected, listController: listController, title: title)
        if canGenerate {
            GenerateItemView(currentSelected: currentSelected, title: title)
        }
        #if !os(tvOS)
        if root.viewControllable.supportsBatchExtraction {
            BatchExtractionView(controller: controller, currentSelected: currentSelected, title: title)
        }
        #endif
        Divider()
        SpaceActionView(root: root, currentSelected: currentSelected, title: title)
        Divider()
        DeleteItemView(root: root, controller: controller, currentSelected: currentSelected, parentItem: parentItem, title: title)
    }
}

private extension ListRootContextMenu {
    var title: String {
        controller.itemName(currentSelected: currentSelected)
    }
    
    var parent: (any ItemDataAccessible)? {
        parentItem ?? controller.parentItem(currentSelected: currentSelected)
    }

    var listDisplayModel: ListDisplayModel {
        listController?.listDisplayModel ?? ListDisplayModel()
    }

    var canGenerate: Bool {
        guard itemGenerationAction.isEnabled,
              let currentSelected,
              let item = root.itemControllable.itemSync(for: currentSelected)
        else {
            return false
        }
        return root.configurable.module == .table && !item.specialCategory
    }
}

/// "Remove from folder" (to the folder's parent, or to root) and "Remove from collection".
/// View structs instead of functions returning view content. See CODE_AUDIT_Folder §8.3.
private struct RemoveFromParentActions: View {
    let root: any ItemRootControllable
    let controller: ContextMenuMultiController
    let listController: (any FolderListControllable)?
    let currentSelected: UUID?
    let parent: (any ItemDataAccessible)?
    let title: String

    var body: some View {
        if controller.hasDifferentFolders(for: parent) {
            RemoveFromParentButton(
                root: root,
                controller: controller,
                listController: listController,
                currentSelected: currentSelected,
                parent: parent,
                title: title,
                oneUp: true
            )
        }
        if parent?.specialCategory ?? false {
            RemoveFromParentButton(
                root: root,
                controller: controller,
                listController: listController,
                currentSelected: currentSelected,
                parent: parent,
                title: title,
                oneUp: false
            )
        }
    }
}

private struct RemoveFromParentButton: View {
    let root: any ItemRootControllable
    let controller: ContextMenuMultiController
    let listController: (any FolderListControllable)?
    let currentSelected: UUID?
    let parent: (any ItemDataAccessible)?
    let title: String
    let oneUp: Bool

    var body: some View {
        Button {
            controller.removeItemsFromFolder(currentSelected: currentSelected, parentId: parent?.id, oneUp: oneUp)
            listController?.update(debounce: false)
        } label: {
            Label {
                Text("Remove \(title) from \(destinationTitle)", bundle: .module)
            } icon: {
                Image(systemName: "rectangle.stack.badge.minus")
            }
        }
    }

    private var destinationTitle: String {
        guard let parent else { return String(localized: "Unknown", bundle: .module) }
        guard parent.isFolder else { return parent.category.title }
        var toName = String(localized: "Root", bundle: .module)
        if oneUp, let parentId = parent.parentId, let parentParent = root.itemControllable.itemSync(for: parentId) {
            toName = parentParent.name
        }
        return String(localized: "\(parent.name) to \(toName)", bundle: .module)
    }
}

private struct GenerateItemView: View {
    @Environment(\.itemGenerationAction) private var itemGenerationAction

    let currentSelected: UUID?
    let title: String

    var body: some View {
        Button {
            guard let currentSelected else { return }
            itemGenerationAction(currentSelected)
        } label: {
            Label {
                Text("Generate from \(title)", bundle: .module)
            } icon: {
                Image(systemName: "gear")
            }
        }
    }
}

private struct SpaceActionView: View {
    @Environment(ScenesManager.self) private var scenesManager

    let root: any ItemRootControllable
    let currentSelected: UUID?
    let title: String

    var body: some View {
        Button {
            ItemPrimaryAction.perform(
                root: root,
                scenesManager: scenesManager,
                itemId: currentSelected
            )
        } label: {
            let isCustom = root.viewControllable.hasCustomSpaceAction
            Label {
                Text(isCustom ? "Play/Roll \(title)" : "View \(title)", bundle: .module)
            } icon: {
                Image(systemName: isCustom ? "play.fill" : "eye")
            }
        }
        #if !os(tvOS)
        .keyboardShortcut(.return, modifiers: [])
        #endif
        .disabled(!ItemPrimaryAction.canPerform(root: root, itemId: currentSelected))
    }
}

private struct EditItemView: View {
    let root: any ItemRootControllable
    let title: String

    var body: some View {
        Button {
            root.navigationModel.openHeaderEditor = true
        } label: {
            Label {
                Text("Edit \(title)", bundle: .module)
            } icon: {
                Image(systemName: "pencil")
            }
        }
        #if !os(tvOS)
        .keyboardShortcut("e", modifiers: [.command, .shift])
        #endif
    }
}

private struct DuplicateItemView: View {
    let controller: ContextMenuMultiController
    let currentSelected: UUID?
    let title: String

    var body: some View {
        Button {
            controller.duplicateItem(currentSelected: currentSelected)
        } label: {
            Label {
                Text("Duplicate \(title)", bundle: .module)
            } icon: {
                Image(systemName: "doc.on.doc")
            }
        }
        #if !os(tvOS)
        .keyboardShortcut("D", modifiers: [.command, .shift])
        #endif
    }
}

private struct DeleteItemView: View {
    @Environment(\.navigator) private var navigator

    let root: any ItemRootControllable
    let controller: ContextMenuMultiController
    let currentSelected: UUID?
    let parentItem: (any ItemDataAccessible)?
    let title: String

    var body: some View {
        Button(role: .destructive) {
            var removingItems: [ItemRowModel] = []
            withAnimation {
                removingItems = controller.deleteItem(currentSelected: currentSelected)
                guard !removingItems.isEmpty else { return }
                root.removeEntryListModel.present(root.editControllable.collectionItemsForRemoval(for: removingItems))
            }
            // Nothing selected: opening the panel showed the previous deletion's list.
            // See CODE_AUDIT_Folder §5.12.
            guard !removingItems.isEmpty else { return }
            navigator.navigate(to: InternalRoute.removeAlert, method: .managedSheet)
        } label: {
            Label {
                Text("Delete \(title)", bundle: .module)
            } icon: {
                Image(systemName: "trash")
            }
        }
        #if !os(tvOS)
        .keyboardShortcut(.delete, modifiers: .command)
        #endif
        // Every collection kind (album, playlist, dice bag, …), not only `.collection`: in a
        // collection's list Delete would remove the item itself. See CODE_AUDIT_Folder §5.29.
        .disabled(parentItem?.category.isCollection ?? false)
    }
}

private struct ExportItemView: View {
    @Environment(\.navigator) private var navigator

    let controller: ContextMenuMultiController
    let currentSelected: UUID?
    let title: String

    var body: some View {
        Button {
            let route = controller.exportItem(currentSelected: currentSelected)
            navigator.navigate(to: route, method: .sheet)
        } label: {
            Label {
                Text("Export \(title)", bundle: .module)
            } icon: {
                Image(systemName: "square.and.arrow.up")
            }
        }
        #if !os(tvOS)
        .keyboardShortcut("e", modifiers: [.command, .control])
        #endif
    }
}

private struct GroupEditView: View {
    @Environment(\.navigator) private var navigator

    let controller: ContextMenuMultiController
    let currentSelected: UUID?
    let title: String

    var body: some View {
        Button {
            let route = controller.groupEditor(currentSelected: currentSelected)
            navigator.navigate(to: route, method: .sheet)
        } label: {
            Label {
                Text("Group editor for \(title)", bundle: .module)
            } icon: {
                Image(systemName: "long.text.page.and.pencil")
            }
        }
        #if !os(tvOS)
        .keyboardShortcut("g", modifiers: [.command, .control])
        #endif
    }
}

/// "Move <item> into <open item> as group value", and a picker for any other item that can host
/// it. Only for one row (not in selection mode), and only where the module has group values
/// (Character, Adventure) and the row can become one: the entry is hidden otherwise.
private struct MoveIntoGroupMenu: View {
    let root: any ItemRootControllable
    let controller: ContextMenuMultiController
    let currentSelected: UUID?
    let listController: (any FolderListControllable)?
    let title: String

    var body: some View {
        if let itemId = currentSelected,
           let editable = root.editControllable as? any EntryDataEditable,
           editable.canAddGroups {
            // The row being right-clicked is not necessarily the open one: the open item is the
            // list's selection.
            let openTarget = openTarget(itemId: itemId, editable: editable)
            if let openTarget {
                Button {
                    move(itemId: itemId, into: openTarget.id, editable: editable)
                } label: {
                    Label {
                        Text("Move \(title) into \(openTarget.name) as group value", bundle: .module)
                    } icon: {
                        Image(systemName: "arrow.turn.down.right")
                    }
                }
            }
            // Computed once for both the check and the menu, and capped. See CODE_AUDIT_26 §7.43.
            let candidates = candidates(itemId: itemId, excluding: openTarget?.id, editable: editable)
            if !candidates.isEmpty {
                Menu {
                    ForEach(candidates) { target in
                        Button(target.name) {
                            move(itemId: itemId, into: target.id, editable: editable)
                        }
                    }
                } label: {
                    Label {
                        Text("Move \(title) into group value of", bundle: .module)
                    } icon: {
                        Image(systemName: "arrow.turn.down.right")
                    }
                }
            }
        }
    }

    private func openTarget(itemId: UUID, editable: any EntryDataEditable) -> FolderRepresentable? {
        guard let openId = root.currentSelectedItemId,
              editable.canMoveIntoGroup(itemId: itemId, into: openId),
              let open = root.itemControllable.itemSync(for: openId) else { return nil }
        return FolderRepresentable(id: openId, name: open.name)
    }

    private func candidates(itemId: UUID, excluding openId: UUID?, editable: any EntryDataEditable) -> [FolderRepresentable] {
        root.itemControllable.itemDataModel.items.compactMap { targetId -> FolderRepresentable? in
            guard targetId != openId,
                  editable.canMoveIntoGroup(itemId: itemId, into: targetId),
                  let target = root.itemControllable.itemSync(for: targetId) else { return nil }
            return FolderRepresentable(id: targetId, name: target.name)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        .prefix(Self.maximumCandidates)
        .map { $0 }
    }

    /// A menu of thousands of items is unusable; the first by name are offered.
    private static let maximumCandidates = 100

    private func move(itemId: UUID, into targetId: UUID, editable: any EntryDataEditable) {
        withAnimation {
            guard editable.moveIntoGroup(itemId: itemId, into: targetId) != nil else { return }
            // The item only changed fields (groupId, hidden) the list does not observe: ask for
            // a fresh list at once, like the sheet's group conversion does.
            listController?.update(debounce: false)
        }
    }
}

#if !os(tvOS)
private struct BatchExtractionView: View {
    @Environment(\.navigator) private var navigator

    let controller: ContextMenuMultiController
    let currentSelected: UUID?
    let title: String

    var body: some View {
        Button {
            let ids = controller.selection(currentSelected: currentSelected)
            navigator.navigate(to: InternalRoute.batchExtraction(ids: ids), method: .sheet)
        } label: {
            Label {
                Text("Extract information for \(title)", bundle: .module)
            } icon: {
                Image(systemName: "sparkles")
            }
        }
        .accessibilityHint(Text("Analyzes selected items with AI", bundle: .module))
    }
}
#endif

#Preview {
    let fixture = FakeItemRootControllerFixture()
    ListRootContextMenu(
        root: fixture.root,
        controller: ContextMenuMultiController(
            editController: fixture.editController,
            itemController: fixture.itemController,
            listModel: fixture.folderListController.listModel
        ),
        parentItem: nil,
        listController: fixture.folderListController
    )
    .padding()
}
