// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftUI

public enum AdventureRoute: Equatable, Hashable, Codable {
    case detail(UUID)
}

extension AdventureRoute: RawRepresentable {
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

extension AdventureRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            DestinationAdventureRouteView(itemId: itemId)
                .navigationDestination(AdventureDetailRoute.self)
                .navigationAutoReceive(AdventureDetailRoute.self)
        }
    }
}

extension AdventureRoute: ItemDetailRoute {
    public func reset(detail: UUID) -> Self {
        AdventureRoute.detail(detail)
    }
    
    public func detail() -> UUID? {
        switch self {
            case .detail(let id): return id
        }
    }
}

struct DestinationAdventureRouteView: View {
    let itemId: UUID

    @Environment(AdventureRootModel.self) private var root
    
    var body: some View {
        DetailRootView(root: root, model: root.itemController.itemOrEmpty(for: itemId))
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
            .environment(root.rootController)
    }
}
