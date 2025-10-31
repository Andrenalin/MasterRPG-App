// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftUI

public enum SpaceNewRoute: Equatable, Hashable, Codable {
    case detail(UUID)
}

extension SpaceNewRoute: RawRepresentable {
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

extension SpaceNewRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            DetailRouteDestinationView(itemId: itemId)
        }
    }
}

extension SpaceNewRoute: ItemDetailRoute {
    public func reset(detail: UUID) -> Self {
        SpaceNewRoute.detail(detail)
    }
    
    public func detail() -> UUID? {
        switch self {
            case .detail(let id): return id
        }
    }
}

struct DetailRouteDestinationView: View {
    let itemId: UUID
    @Environment(SpaceRoot.self) private var root
    
    var body: some View {
        SpaceDetailEditor(editController: root.editController(type: .main), model: root.itemController.itemOrEmpty(for: itemId))
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
            .environment(root.rootController)
    }
}
