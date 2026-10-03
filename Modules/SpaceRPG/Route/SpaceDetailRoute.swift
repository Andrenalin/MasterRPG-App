// @copyright André Trettin

import CoreRPG
import SwiftUI

public enum SpaceDetailRoute: Equatable, Hashable, Codable {
    case folder(UUID)
    case folderInline(UUID)
}

extension SpaceDetailRoute: RawRepresentable {
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

extension SpaceDetailRoute: NavigationDestination {
    public var body: some View {
        SpaceDetailRouteDestinationView(route: self)
    }
}

extension SpaceDetailRoute: ItemDetailRoute {
    public static func detailRoute(itemId: UUID) -> Self {
        SpaceDetailRoute.folder(itemId)
    }

    public func reset(detail: UUID) -> Self {
        SpaceDetailRoute.folder(detail)
    }
    
    public func detail() -> UUID? {
        switch self {
            case .folder(let id): return id
            case .folderInline(let id): return id
        }
    }
}

struct SpaceDetailRouteDestinationView: View {
    let route: SpaceDetailRoute

    @Environment(SpaceRootModel.self) private var root
    
    var body: some View {
        switch route {
        case .folder(let itemId):
            if let model = root.itemController.itemSync(for: itemId), let parentId = model.parentId, let parentModel = root.itemController.itemSync(for: parentId) {
                DetailFolderControllerReader(listController: root.folderListController, itemId: itemId, parentModel: parentModel, navigationModel: root.navigationModel) { folderListController in
                    DetailListView(root: root, model: model, folderListController: folderListController)
                }
            }
        case .folderInline(let itemId):
            if let model = root.itemController.itemSync(for: itemId), let parentId = model.parentId, let parentModel = root.itemController.itemSync(for: parentId) {
                DetailFolderControllerReader(listController: root.folderListController, itemId: itemId, parentModel: parentModel, navigationModel: root.navigationModel) { folderListController in
                    DetailFolderListView(root: root, model: model, folderListController: folderListController, isSubFolder: true)
                }
            }
        }
    }
}

#Preview(traits: .mockData) {
    SpaceDetailRouteDestinationView(route: .folder(SpaceModel.previewId))
}
