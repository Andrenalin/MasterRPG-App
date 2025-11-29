// @copyright André Trettin

import CoreRPG

import SwiftUI

public enum SpaceDetailRoute: Equatable, Hashable, Codable {
    case folder(UUID)
}

extension SpaceDetailRoute: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .folder(let id): "folder/\(id.uuidString)"
        }
    }

    public init?(rawValue: String) {
        let values = rawValue.split(separator: "/")
        guard let token = values.first, let idString = values.last, let uuid = UUID(uuidString: String(idString)) else { return nil }
        switch token {
        case "folder": self = .folder(uuid)
        default: return nil
        }
    }
}

extension SpaceDetailRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .folder(let itemId):
            SpaceDetailRouteDestinationView(itemId: itemId)
        }
    }
}

extension SpaceDetailRoute: ItemDetailRoute {
    public func reset(detail: UUID) -> Self {
        SpaceDetailRoute.folder(detail)
    }
    
    public func detail() -> UUID? {
        switch self {
            case .folder(let id): return id
        }
    }
}

struct SpaceDetailRouteDestinationView: View {
    let itemId: UUID

    @Environment(SpaceRootModel.self) private var root
    
    var body: some View {
        DetailListView(root: root, model: root.itemController.itemOrEmpty(for: itemId))
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
            .environment(root.folderListController.detailInspectorModel)
            .environment(root.rootController)
    }
}
