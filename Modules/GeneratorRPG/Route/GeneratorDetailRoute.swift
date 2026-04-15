// @copyright André Trettin

import CoreRPG

import SwiftUI

public enum GeneratorDetailRoute: Equatable, Hashable, Codable {
    case folder(UUID)
}

extension GeneratorDetailRoute: RawRepresentable {
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

extension GeneratorDetailRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .folder(let itemId):
            GeneratorDetailRouteDestinationView(itemId: itemId)
        }
    }
}

extension GeneratorDetailRoute: ItemDetailRoute {
    public func reset(detail: UUID) -> Self {
        GeneratorDetailRoute.folder(detail)
    }
    
    public func detail() -> UUID? {
        switch self {
            case .folder(let id): return id
        }
    }
}

struct GeneratorDetailRouteDestinationView: View {
    let itemId: UUID

    @Environment(GeneratorRootModel.self) private var root
    
    var body: some View {
        DetailListView(root: root, model: root.itemController.itemOrEmpty(for: itemId))
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
            .environment(root.rootController)
    }
}
