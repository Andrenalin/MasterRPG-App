// @copyright André Trettin

import SwiftUI

public struct EffectedLinkAction: View {
    public init(itemControllable: any ItemControllable, removeEntryList: RemoveEntryListModel, overwrite: Bool = false, action: @escaping ([ItemRowModel]) async -> Void) {
        self.itemControllable = itemControllable
        self.removeEntryList = removeEntryList
        self.overwrite = overwrite
        self.action = action
    }
    
    let itemControllable: any ItemControllable
    let removeEntryList: RemoveEntryListModel
    let overwrite: Bool
    let action: ([ItemRowModel]) async -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
        
    public var body: some View {
        NavigationStack {
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
            .navigationTitle(Text("Mark for remove \(removeEntryList.linkTree.filter { $0.canRemoved }.count) Item", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .destructiveAction) {
                    Button {
                        let linkItems = removeEntryList.linkTree.compactMap { $0.canRemoved ? $0.item : nil }
                        Task {
                            await action(linkItems)
                            dismiss()
                        }
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
                    Button {
                        withAnimation { dismiss() }
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
                removeEntryList.linkTree = await EffectedLinkAction.linkTree(itemControllable: itemControllable, removeItems: removeEntryList.removeItems)
            }
        }
    }
}

private extension EffectedLinkAction {
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
    
    func itemName(item: RemoveLinkTreeModel) -> String {
        var name = itemControllable.nameSync(itemId: item.item.itemId)
        if let entryId = item.item.entryId, let model = itemControllable.itemSync(for: item.item.itemId), let index = model.entries.firstIndex(where: { $0.id == entryId }) {
            name = "\(name) --- \(model.entries[index].name)"
        }
        return name
    }
    
    static func effectedItems(itemControllable: any ItemControllable, for item: ItemRowModel) async -> [EffectedItemModel] {
        []
        //itemControllable.usedLinks(for: item)
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
