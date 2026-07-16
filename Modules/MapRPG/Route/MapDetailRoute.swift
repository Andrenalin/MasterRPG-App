// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import SwiftUI

public enum MapDetailRoute: Equatable, Hashable, Codable {
    case folder(UUID)
    case folderInline(UUID)
#if !os(tvOS)
    case mapExtraction(UUID)
#endif
}

extension MapDetailRoute: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .folder(let id): "folder/\(id.uuidString)"
        case .folderInline(let id): "folderInline/\(id.uuidString)"
#if !os(tvOS)
        case .mapExtraction(let id): "mapExtraction/\(id.uuidString)"
#endif
        }
    }

    public init?(rawValue: String) {
        let values = rawValue.split(separator: "/")
        guard let token = values.first, let idString = values.last, let uuid = UUID(uuidString: String(idString)) else { return nil }
        switch token {
        case "folder": self = .folder(uuid)
        case "folderInline": self = .folderInline(uuid)
#if !os(tvOS)
        case "mapExtraction": self = .mapExtraction(uuid)
#endif
        default: return nil
        }
    }
}

extension MapDetailRoute: NavigationDestination {
    public var body: some View {
        MapDetailRouteDestinationView(route: self)
    }
}

extension MapDetailRoute: ItemDetailRoute {
    public static func detailRoute(itemId: UUID) -> Self {
        MapDetailRoute.folder(itemId)
    }

    public func reset(detail: UUID) -> Self {
        MapDetailRoute.folder(detail)
    }

    public func detail() -> UUID? {
        switch self {
            case .folder(let id): return id
            case .folderInline(let id): return id
#if !os(tvOS)
            case .mapExtraction(let id): return id
#endif
        }
    }
}

struct MapDetailRouteDestinationView: View {
    let route: MapDetailRoute

    @Environment(MapRootModel.self) private var root

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

#if !os(tvOS)
        case .mapExtraction(let itemId):
            MapExtractionDestination(itemId: itemId)
#endif
        }
    }
}

#Preview(traits: .mockData) { MapDetailRouteDestinationView(route: .folder(MapModel.previewId)) }
