// @copyright André Trettin

import SwiftUI
import SwiftData

public struct EffectedLinkActionPanelView: View {
    public init(root: any ItemRootControllable, overwrite: Bool = false, action: (([ItemRowModel]) -> Void)? = nil) {
        self.root = root
        self.overwrite = overwrite
        self.action = action
    }
    
    let root: ItemRootControllable
    let overwrite: Bool
    let action: (([ItemRowModel]) -> Void)?
    
    @Environment(\.navigator) private var navigator
    @Environment(\.colorScheme) private var colorScheme
        
    public var body: some View {
        ManagedNavigationStack {
            List {
                ForEach(removeEntryList.linkTree) { item in
                    Group {
                        if let link = item.link {
                            Label(link.title, systemImage: link.module.icon)
                        } else {
                            linkHeaderView(for: item)
                        }
                    }
                    .listRowInsets(item.link == nil ? .none : EdgeInsets(top: 0, leading: 40, bottom: 0, trailing: 0))
                    .listRowBackground(colorBackground(for: item))
                }
            }
            .frame(minHeight: 300)
            .navigationTitle(Text("Mark for remove \(removeEntryList.linkTree.filter { $0.canRemoved }.count) Item", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .destructiveAction) {
                    Button {
                        let removedItems = removeEntryList.linkTree.compactMap { $0.canRemoved ? $0.item : nil }
                        let restoredItems = removeEntryList.linkTree.compactMap { $0.canRemoved ? nil : $0.item }
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
                        restoreItems(models: removeEntryList.linkTree.map { $0.item })
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
        .onChange(of: removeEntryList.removeItems, initial: true) {
            Task {
                removeEntryList.linkTree = await EffectedLinkActionPanelView.linkTree(itemControllable: root.itemControllable, removeItems: removeEntryList.removeItems)
            }
        }
    }
}

#Preview {
    EffectedLinkActionPanelView(root: ItemRootController.fake)
}

private extension EffectedLinkActionPanelView {
    @MainActor func removeItems(models: [ItemRowModel]) {
        for model in models {
            root.editControllable.markForDeletion(itemId: model.itemId)
        }
    }
    
    @MainActor func restoreItems(models: [ItemRowModel]) {
        for model in models {
            root.editControllable.restore(itemId: model.itemId)
        }
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
    
    func colorBackground(for item: RemoveLinkTreeModel) -> Color {
        if item.link == nil {
#if os(macOS)
            return .clear
#else
            return colorScheme == .dark ? Color.black : Color.white
#endif
        } else {
            return colorScheme == .dark ? Color.red.opacity(0.25) : Color.red.opacity(0.7)
        }
    }
    
    
    func linkHeaderView(for item: RemoveLinkTreeModel) -> some View {
        HStack {
            if item.counter == 0 {
                Image(systemName: "checkmark")
            } else {
                if item.canRemoved {
                    Button {
                        guard let index = removeEntryList.linkTree.firstIndex(where: { $0.id == item.id }) else { return }
                        withAnimation { removeEntryList.linkTree[index].canRemoved.toggle() }
                    } label: {
                        Label {
                            Text("Unmark", bundle: .module)
                        } icon: {
                            Image(systemName: "checkmark.seal")
                        }
                    }
                } else {
                    Button(role: .destructive) {
                        guard let index = removeEntryList.linkTree.firstIndex(where: { $0.id == item.id }) else { return }
                        withAnimation { removeEntryList.linkTree[index].canRemoved.toggle() }
                    } label: {
                        Label {
                            Text("Mark", bundle: .module)
                        } icon: {
                            Image(systemName: "xmark.seal")
                        }
                    }
                }
            }
            Text(itemName(item: item))
#if !os(tvOS)
                .badge(item.counter)
#endif
        }
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
    
    static func effectedItems(itemControllable: any ItemControllable, for item: ItemRowModel) async -> [EffectedItemModel] {
        let linkRegisterController = itemControllable.linkRegisterController
        return linkRegisterController.used(for: item)
    }
    
    static func linkTree(itemControllable: any ItemControllable, removeItems: [ItemRowModel]) async -> [RemoveLinkTreeModel] {
        var result: [RemoveLinkTreeModel] = []
        for item in removeItems {
            let links = await effectedItems(itemControllable: itemControllable, for: item)
            var items = [RemoveLinkTreeModel(item: item, link: nil, canRemoved: links.isEmpty, counter: links.count)]
            items.append(contentsOf: links.map {
                RemoveLinkTreeModel(item: ItemRowModel(itemId: $0.id, typeId: item.typeId), link: $0, canRemoved: false, counter: 0)
            })
            result.append(contentsOf: items)
        }
        return result
    }
}
