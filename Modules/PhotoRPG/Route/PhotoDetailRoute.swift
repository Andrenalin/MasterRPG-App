// @copyright André Trettin

import CoreRPG
import SwiftUI

public enum PhotoDetailRoute: Equatable, Hashable, Codable {
    case folder(UUID)
    case folderInline(UUID)
}

extension PhotoDetailRoute: RawRepresentable {
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

extension PhotoDetailRoute: NavigationDestination {
    public var body: some View {
        PhotoDetailRouteDestinationView(route: self)
    }
}

extension PhotoDetailRoute: ItemDetailRoute {
    public static func detailRoute(itemId: UUID) -> Self {
        PhotoDetailRoute.folder(itemId)
    }

    public func reset(detail: UUID) -> Self {
        PhotoDetailRoute.folder(detail)
    }
    
    public func detail() -> UUID? {
        switch self {
            case .folder(let id): return id
            case .folderInline(let id): return id
        }
    }
}

struct PhotoDetailRouteDestinationView: View {
    let route: PhotoDetailRoute

    @Environment(PhotoRootModel.self) private var root

    var body: some View {
        switch route {
        case .folder(let itemId):
            if let model = root.itemController.itemSync(for: itemId), let parentId = model.parentId, let parentModel = root.itemController.itemSync(for: parentId) {
                DetailListView(root: root, model: model, folderListController: root.folderListController.copy(listModel: FolderListModel(parentModel: parentModel, navigationModel: root.navigationModel)))
            }
            
        case .folderInline(let itemId):
            if let model = root.itemController.itemSync(for: itemId), let parentId = model.parentId, let parentModel = root.itemController.itemSync(for: parentId) {
                DetailFolderListView(root: root, model: model, folderListController: root.folderListController.copy(listModel: FolderListModel(parentModel: parentModel, navigationModel: root.navigationModel)), isSubFolder: true)
            }
        }
    }
}
