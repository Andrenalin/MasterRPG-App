// @copyright André Trettin

import CoreRPG
import SwiftUI

public enum AudioDetailRoute: Equatable, Hashable, Codable {
    case folder(UUID)
    case folderInline(UUID)
}

extension AudioDetailRoute: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .folder(let id): "folder/\(id.uuidString)"
        case .folderInline(let id): "folderInline/\(id.uuidString)"
        }
    }

    public init?(rawValue: String) {
        let values = rawValue.split(separator: "/")
        guard let token = values.first, let idString = values.last, let uuid = UUID(uuidString: String(idString)) else { return nil }
        switch token {
        case "folder": self = .folder(uuid)
        case "folderInline": self = .folderInline(uuid)
        default: return nil
        }
    }
}

extension AudioDetailRoute: NavigationDestination {
    public var body: some View {
        AudioDetailRouteDestinationView(route: self)
    }
}

extension AudioDetailRoute: ItemDetailRoute {
    public static func detailRoute(itemId: UUID) -> Self {
        AudioDetailRoute.folder(itemId)
    }

    public func reset(detail: UUID) -> Self {
        AudioDetailRoute.folder(detail)
    }
    
    public func detail() -> UUID? {
        switch self {
            case .folder(let id): return id
            case .folderInline(let id): return id
        }
    }
}

struct AudioDetailRouteDestinationView: View {
    let route: AudioDetailRoute

    @Environment(AudioRootModel.self) private var root
    
    var body: some View {
        switch route {
        case .folder(let itemId):
            if let model = root.itemController.itemSync(for: itemId), let parentId = model.parentId, let parentModel = root.itemController.itemSync(for: parentId) {
                DetailListView(root: root, model: model, folderListController: root.folderListController.copy(listModel: FolderListModel(parentModel: parentModel, navigationModel: root.navigationModel)))
            }
        case .folderInline(let itemId):
            if let item = root.itemController.itemSync(for: itemId) {
                DetailFolderListView(root: root, model: item, folderListController: detailFolderListController(item: item))
            }
        }
    }
    
    private func detailFolderListController(item: AudioModel) -> FolderListController {
        root.folderListController.copy(listModel: currentListModel(item: item))
    }
    
    private func currentListModel(item: AudioModel) -> FolderListModel {
        if let existing = root.navigationModel.folderModels[item.id] {
            return existing
        }
        
        let newModel = root.folderListController.copyModel(parentModel: item)
        root.navigationModel.folderModels[item.id] = newModel
        return newModel
    }

}
