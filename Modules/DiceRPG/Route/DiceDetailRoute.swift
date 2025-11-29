// @copyright André Trettin

import CoreRPG
import CoreExternalRPG
import SwiftUI

public enum DiceDetailRoute: Equatable, Hashable, Codable {
    case folder(UUID)
}

extension DiceDetailRoute: RawRepresentable {
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

extension DiceDetailRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .folder(let itemId):
            DiceDetailRouteDestinationView(itemId: itemId)
        }
    }
}

extension DiceDetailRoute: ItemDetailRoute {
    public func reset(detail: UUID) -> Self {
        DiceDetailRoute.folder(detail)
    }
    
    public func detail() -> UUID? {
        switch self {
            case .folder(let id): return id
        }
    }
}

struct DiceDetailRouteDestinationView: View {
    let itemId: UUID

    @Environment(DiceRootModel.self) private var root
    
    var body: some View {
        DetailListView(root: root, model: root.itemController.itemOrEmpty(for: itemId))
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
            .environment(root.folderListController.detailInspectorModel)
            .environment(root.rootController)
    }
}
