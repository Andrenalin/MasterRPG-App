// @copyright André Trettin

import SwiftUI

public struct AffectedLinkActionPanelView: View {
    public init(root: any ItemRootControllable, overwrite: Bool = false, action: (([ItemRowModel]) -> Void)? = nil) {
        self.root = root
        self.overwrite = overwrite
        self.action = action
    }
    
    let root: ItemRootControllable
    let overwrite: Bool
    let action: (([ItemRowModel]) -> Void)?
    
    @Environment(\.navigator) private var navigator
    @Environment(\.appTheme) private var theme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    /// Set by Remove and Cancel. A sheet dismissed any other way (swipe, Escape outside the
    /// button) counts as Cancel. See CODE_AUDIT_Folder §5.12.
    @State private var isResolved = false
        
    public var body: some View {
        ManagedNavigationStack {
            List {
                ForEach(removeEntryList.linkTree) { item in
                    Group {
                        if let link = item.link {
                            Label(link.title, systemImage: link.module.icon)
                        } else {
                            AffectedLinkHeaderRow(item: item, name: itemName(item: item), removeEntryList: removeEntryList)
                        }
                    }
                    .listRowInsets(item.link == nil ? .none : EdgeInsets(top: 0, leading: 40, bottom: 0, trailing: 0))
                    .listRowBackground(colorBackground(for: item))
                }
            }
            .themedListSurface()
            .frame(minHeight: 300)
            // Plural-aware: "Mark for remove N Item" read wrong for any count but one.
            // See CODE_AUDIT_Folder §8.5.
            .navigationTitle(Text("Mark \(removeEntryList.linkTree.filter { $0.canRemoved }.count) items for removal", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .destructiveAction) {
                    Button {
                        let removedItems = removeEntryList.linkTree.compactMap { $0.canRemoved ? $0.item : nil }
                        let restoredItems = removeEntryList.linkTree.compactMap { $0.canRemoved ? nil : $0.item }
                        isResolved = true
                        if let action {
                            action(removedItems)
                        } else {
                            removeItems(models: removedItems)
                            restoreItems(models: restoredItems)
                        }
                        navigator.dismiss()
                    } label: {
                        Label {
                            Text("Remove", bundle: .module)
                        } icon: {
                            Image(systemName: "trash")
                        }
                    }
                    .disabled(disabledRemove)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        isResolved = true
                        restoreItems(models: removeEntryList.removeItems)
                        navigator.dismiss()
                    } label: {
                        Label {
                            Text("Cancel", bundle: .module)
                        } icon: {
                            Image(systemName: "xmark")
                        }
                    }
                }
            }
        }
        // `.task(id:)` cancels the previous run automatically when `removeItems` changes,
        // so two rapid selection changes can't have their link-scan results land out of
        // order — `Task { }` inside `.onChange` had no such cancellation. See
        // CODE_AUDIT_EditItem §3.6.
        .task(id: removeEntryList.removeItems) {
            removeEntryList.linkTree = await AffectedLinkActionPanelView.linkTree(itemControllable: root.itemControllable, removeItems: removeEntryList.removeItems)
        }
        .onDisappear {
            // The items were trashed before the panel opened; a dismissal without Remove keeps
            // nothing trashed the user did not confirm. The list is cleared either way, so a
            // later panel never shows (or restores) this deletion's items.
            // See CODE_AUDIT_Folder §5.12.
            if !isResolved, action == nil {
                restoreItems(models: removeEntryList.removeItems)
            }
            removeEntryList.removeItems = []
            removeEntryList.linkTree = []
        }
    }
}

#Preview {
    AffectedLinkActionPanelView(root: ItemRootController.fake)
}

private extension AffectedLinkActionPanelView {
    @MainActor func removeItems(models: [ItemRowModel]) {
        for model in models {
            root.editControllable.markForDeletion(itemId: model.itemId)
        }
    }
    
    /// Restores `models` together, so a folder and its children come back as they were.
    /// See CODE_AUDIT_Folder §5.4.
    @MainActor func restoreItems(models: [ItemRowModel]) {
        root.editControllable.restore(itemIds: models.map(\.itemId))
        root.folderListControllable.scheduleSearch()
    }

    var removeEntryList: RemoveEntryListModel {
        root.removeEntryListModel
    }
    
    var disabledRemove: Bool {
        if overwrite {
            return false
        }
        return removeEntryList.linkTree.filter { $0.canRemoved }.isEmpty
    }
    
    /// Item rows use the theme's panel colour; rows of items that link to it use the system red,
    /// which adapts to dark mode and increased contrast, stronger when contrast is increased.
    /// Fixed black, white and red ignored both. See CODE_AUDIT_Folder §8.5.
    func colorBackground(for item: RemoveLinkTreeModel) -> Color {
        if item.link == nil {
            return theme.panelColor
        }
        return Color.red.opacity(colorSchemeContrast == .increased ? 0.45 : 0.25)
    }

    private var nameNotSet: String {
        String(localized: "Untitled", bundle: .module).localizedString
    }
    
    func itemName(item: RemoveLinkTreeModel) -> String {
        guard let model = root.itemControllable.itemSync(for: item.item.itemId) else { return "" }
        var name = model.name
        if name.isEmpty {
            name = nameNotSet
        }
        let fileWarning: String = model.fileUrl != nil ? String(localized: "Path: \(model.url?.path(percentEncoded: false) ?? "Unknown")", bundle: .module).localizedString : ""
        if let entryId = item.item.entryId, let index = model.entries.firstIndex(where: { $0.id == entryId }) {
            name = "\(name) --- \(model.entries[index].name)"
        }
        if !fileWarning.isEmpty {
            name.append("\n\(fileWarning)")
        }
        return name
    }
    
    static func affectedItems(itemControllable: any ItemControllable, for item: ItemRowModel) async -> [AffectedItemModel] {
        let linkRegisterController = itemControllable.linkRegisterController
        return linkRegisterController.used(for: item)
    }
    
    static func linkTree(itemControllable: any ItemControllable, removeItems: [ItemRowModel]) async -> [RemoveLinkTreeModel] {
        var result: [RemoveLinkTreeModel] = []
        for item in removeItems {
            let links = await affectedItems(itemControllable: itemControllable, for: item)
            var items = [RemoveLinkTreeModel(item: item, link: nil, canRemoved: links.isEmpty, counter: links.count)]
            items.append(contentsOf: links.map {
                RemoveLinkTreeModel(item: ItemRowModel(itemId: $0.id, typeId: item.typeId), link: $0, canRemoved: false, counter: 0)
            })
            result.append(contentsOf: items)
        }
        return result
    }
}

/// An item the panel deletes, with its Mark/Unmark toggle and the number of items linking to it.
/// A view struct instead of a function returning view content. See CODE_AUDIT_Folder §8.3.
private struct AffectedLinkHeaderRow: View {
    let item: RemoveLinkTreeModel
    let name: String
    let removeEntryList: RemoveEntryListModel

    var body: some View {
        HStack {
            if item.counter == 0 {
                Image(systemName: "checkmark")
            } else if item.canRemoved {
                Button(action: toggle) {
                    Label {
                        Text("Unmark", bundle: .module)
                    } icon: {
                        Image(systemName: "checkmark.seal")
                    }
                }
            } else {
                Button(role: .destructive, action: toggle) {
                    Label {
                        Text("Mark", bundle: .module)
                    } icon: {
                        Image(systemName: "xmark.seal")
                    }
                }
            }
            Text(name)
#if !os(tvOS)
                .badge(item.counter)
#endif
        }
    }

    private func toggle() {
        guard let index = removeEntryList.linkTree.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation { removeEntryList.linkTree[index].canRemoved.toggle() }
    }
}
