// @copyright André Trettin

import CoreRPG
import SwiftUI

public enum DiceDetailRoute: Equatable, Hashable, Codable {
    case folder(UUID)
    case folderInline(UUID)
}

extension DiceDetailRoute: RawRepresentable {
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
        case "folderInline": self = .folder(uuid)
        default: return nil
        }
    }
}

extension DiceDetailRoute: NavigationDestination {
    public var body: some View {
        DiceDetailRouteDestinationView(route: self)
    }
}

extension DiceDetailRoute: ItemDetailRoute {
    public func reset(detail: UUID) -> Self {
        DiceDetailRoute.folder(detail)
    }
    
    public func detail() -> UUID? {
        switch self {
            case .folder(let id): return id
            case .folderInline(let id): return id
        }
    }
}

struct DiceDetailRouteDestinationView: View {
    let route: DiceDetailRoute

    @Environment(DiceRootModel.self) private var root

    var body: some View {
        switch route {
        case .folder(let itemId):
            DetailListView(root: root, model: root.itemController.itemOrEmpty(for: itemId))

        case .folderInline(let itemId):
            DetailFolderListView(root: root, model: root.itemController.itemOrEmpty(for: itemId))
        }
    }
}
