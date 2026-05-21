// @copyright André Trettin

import CoreRPG
import SwiftUI

public enum CharacterDetailRoute: Equatable, Hashable, Codable {
    case folder(UUID)
    case folderInline(UUID)
}

extension CharacterDetailRoute: RawRepresentable {
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

extension CharacterDetailRoute: NavigationDestination {
    public var body: some View {
        CharacterDetailRouteDestinationView(route: self)
    }
}

extension CharacterDetailRoute: ItemDetailRoute {
    public static func detailRoute(itemId: UUID) -> Self {
        CharacterDetailRoute.folder(itemId)
    }

    public func reset(detail: UUID) -> Self {
        CharacterDetailRoute.folder(detail)
    }
    
    public func detail() -> UUID? {
        switch self {
            case .folder(let id): return id
            case .folderInline(let id): return id
        }
    }
}

struct CharacterDetailRouteDestinationView: View {
    let route: CharacterDetailRoute

    @Environment(CharacterRootModel.self) private var root

    var body: some View {
        switch route {
        case .folder(let itemId):
            DetailListView(root: root, model: root.itemController.itemOrEmpty(for: itemId))

        case .folderInline(let itemId):
            DetailFolderListView(root: root, model: root.itemController.itemOrEmpty(for: itemId))
        }
    }
}
