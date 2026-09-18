// @copyright André Trettin


import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    DestinationAdventureRouteView(itemId: AdventureModel.previewId)
}

public enum AdventureRoute: Equatable, Hashable, Codable {
    case detail(UUID)
}

extension AdventureRoute: RawRepresentable {
    public var rawValue: String {
        switch self {
            case .detail(let id): TaggedIdRoute.rawValue(token: "detail", id: id)
        }
    }

    public init?(rawValue: String) {
        guard let route = TaggedIdRoute.parse(rawValue, resolve: { token, id -> Self? in
            switch token {
            case "detail": return .detail(id)
            default: return nil
            }
        }) else { return nil }
        self = route
    }
}

extension AdventureRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            DestinationAdventureRouteView(itemId: itemId)
                .navigationAutoReceive(AdventureDetailRoute.self)
        }
    }
}

extension AdventureRoute: ItemDetailRoute {
    public static func detailRoute(itemId: UUID) -> Self {
        AdventureRoute.detail(itemId)
    }

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
        let _ = Self.printViewChangesOnlyInDebug()
        
        if let model = root.itemController.itemSync(for: itemId) {
            DetailRootView(root: root, model: model)
        }
    }
}
