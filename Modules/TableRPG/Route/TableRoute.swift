// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftUI

public enum TableRoute: Equatable, Hashable, Codable {
    case detail(UUID)
}

extension TableRoute: RawRepresentable {
    public var rawValue: String {
        switch self {
            case .detail(let id): "detail/\(id.uuidString)"
        }
    }

    public init?(rawValue: String) {
        let values = rawValue.split(separator: "/")
        guard let token = values.first, let idString = values.last, let uuid = UUID(uuidString: String(idString)) else { return nil }
        switch token {
            case "detail": self = .detail(uuid)
            default: return nil
        }
    }
}

extension TableRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            DestinationTableRouteView(itemId: itemId)
                .navigationDestination(TableDetailRoute.self)
                .navigationAutoReceive(TableDetailRoute.self)
        }
    }
}

extension TableRoute: ItemDetailRoute {
    public func reset(detail: UUID) -> Self {
        TableRoute.detail(detail)
    }
    
    public func detail() -> UUID? {
        switch self {
            case .detail(let id): return id
        }
    }
}

struct DestinationTableRouteView: View {
    let itemId: UUID

    @Environment(TableRootModel.self) private var root
    
    var body: some View {
        DetailRootView(root: root, model: root.itemController.itemOrEmpty(for: itemId))
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
            .environment(root.rootController)
    }
}
