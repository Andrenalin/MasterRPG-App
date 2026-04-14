// @copyright André Trettin

import CoreRPG

import SwiftUI

public enum DiceRoute: Equatable, Hashable, Codable {
    case detail(UUID)
}

extension DiceRoute: RawRepresentable {
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

extension DiceRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            DiceRouteDestinationView(itemId: itemId)
                .navigationAutoReceive(DiceDetailRoute.self)
        }
    }
}

extension DiceRoute: ItemDetailRoute {
    public func reset(detail: UUID) -> Self {
        DiceRoute.detail(detail)
    }
    
    public func detail() -> UUID? {
        switch self {
            case .detail(let id): return id
        }
    }
}

struct DiceRouteDestinationView: View {
    let itemId: UUID

    @Environment(DiceRootModel.self) private var root
    
    var body: some View {
        if let model = root.itemController.itemSync(for: itemId) {
            DetailRootView(root: root, model: model)
                .environment(root.listDisplayModel)
                .environment(root.searchModel)
                .environment(root.rootController)
        }
    }
}
