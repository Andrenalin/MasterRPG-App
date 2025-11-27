// @copyright André Trettin

import AndrenalinKit
import Foundation
import RPGMaps
import RPGValues
import TableRPG
import WeatherRPG

@MainActor
struct LinkRegisterController: Sendable {
    init(root: AdventureRootModel) {
        self.root = root
        self.model = LinkRegisterListModel()
    }
    
    weak var root: AdventureRootModel!
    @MainActor let model: LinkRegisterListModel
}

extension LinkRegisterController: LinkRegisterControllable {
    @MainActor
    public func used(for link: ItemRowModel) -> [EffectedItemModel] {
        let links: [LinkRegisterModel]
        if let entryId = link.entryId {
            links = model.entries[entryId, default: []]
        } else {
            links = model.items[link.itemId, default: []]
        }
        return links.map {
            var item: (any ItemDataAccessable)?
            switch $0.source.typeId {
            case .adventure:
                item = root.itemControllable.itemSync(for: $0.source.itemId)
            case .map:
                item = root.mapRoot.itemControllable.itemSync(for: $0.source.itemId)
            case .value:
                item = root.valueRoot.itemControllable.itemSync(for: $0.source.itemId)
            case .table:
                item = root.tableRoot.itemControllable.itemSync(for: $0.source.itemId)
            case .weather:
                item = root.weatherRoot.itemControllable.itemSync(for: $0.source.itemId)
            default:
                return EffectedItemModel(id: $0.destination.itemId, name: "Module \($0.source.typeId) not supported", module: $0.source.typeId)
            }
            guard let item else { 
                return EffectedItemModel(id: $0.destination.itemId, name: "Module \($0.source.typeId) registered but item is gone", module: $0.source.typeId)
            }
            var entryName: String? = nil
            if let entryId = $0.source.entryId {
                entryName = item[entryId].name
            }
            return EffectedItemModel(id: UUID(), name: item.name, entryName: entryName, module: $0.source.typeId)
        }
    }
    
    @MainActor
    public func repairLinks(for items: [ItemRowModel]) {
        for item in items {
            let links: [LinkRegisterModel]
            if let entryId = item.entryId {
                links = model.entries[entryId, default: []]
            } else {
                links = model.items[item.itemId, default: []]
            }
            for link in links {
                switch link.source.typeId {
                case .adventure:
                    root.linkController.validateLinks(on: link.source.itemId)
                case .map:
                    root.mapRoot.linkControllable.validateLinks(on: link.source.itemId)
                case .value:
                    root.valueRoot.linkControllable.validateLinks(on: link.source.itemId)
                case .table:
                    root.tableRoot.linkControllable.validateLinks(on: link.source.itemId)
                case .weather:
                    root.weatherRoot.linkControllable.validateLinks(on: link.source.itemId)
                default:
                    break
                }
            }
        }
    }
}
