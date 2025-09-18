// @copyright André Trettin

import SwiftUI
import SwiftData

@Observable
public final class RemoveEntryListModel {
    public init(removeItems: [ItemRowModel] = []) {
        self.removeItems = removeItems
        self.linkTree = []
    }

    public var removeItems: [ItemRowModel] = []
    public var effectedLink: [EffectedItemModel] = []
    var showDeleteAlert: Bool = false
    var linkTree: [RemoveLinkTreeModel] = []
}

public struct EffectedLinkAction: View {
    public init(root: any ItemRootControllable, overwrite: Bool = false, action: (([ItemRowModel]) -> Void)? = nil) {
        self.root = root
        self.overwrite = overwrite
        self.action = action
    }
    
    let root: ItemRootControllable
    let overwrite: Bool
    let action: (([ItemRowModel]) -> Void)?
    
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
                        if let action {
                            action(linkItems)
                        } else {
                            removeItems(models: linkItems)
                        }
                        dismiss()
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
                removeEntryList.linkTree = await EffectedLinkAction.linkTree(itemControllable: root.itemControllable, removeItems: removeEntryList.removeItems)
            }
        }
    }
}

private extension EffectedLinkAction {
    @MainActor func removeItems(models: [ItemRowModel]) {
        models.forEach {
            if let item = root.itemControllable.item(for: $0.itemId) {
                root.editControllable.delete(item: item)
            }
        }
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
    
    func itemName(item: RemoveLinkTreeModel) -> String {
        guard let model = root.itemControllable.item(for: item.item.itemId) else { return "" }
        var name = model.name
        if let entryId = item.item.entryId, let index = model.entries.firstIndex(where: { $0.id == entryId }) {
            name = "\(name) --- \(model.entries[index].name)"
        }
        return name
    }
    
    static func effectedItems(itemControllable: any ItemControllable, for item: ItemRowModel) async -> [EffectedItemModel] {
        let controller = LinkRegisterController(container: itemControllable.container)
        return controller.effectedItems(targetId: item.itemId, targetEntryId: item.entryId, targetModule: item.typeId)
        
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

struct RemoveLinkTreeModel: Identifiable {
    var item: ItemRowModel
    var link: EffectedItemModel?
    var canRemoved: Bool
    var counter: Int
    
    var id: UUID {
        item.entryId ?? item.itemId
    }
}

public struct EffectedItemModel: Equatable, Hashable, Identifiable, Sendable {
    public init(id: UUID, name: String, entryName: String? = nil, module: NetworkModules) {
        self.id = id
        self.name = name
        self.entryName = entryName
        self.module = module
    }
    
    public let id: UUID
    public let name: String
    public let entryName: String?
    public let module: NetworkModules
    
    var title: String {
        guard let entryName else {
            return name
        }
        return "\(name) --- \(entryName)"
    }
}
