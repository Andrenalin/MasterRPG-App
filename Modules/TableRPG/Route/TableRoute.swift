// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    TableRouteDestinationView(itemId: TableModel.previewId)
}

public enum TableRoute: Equatable, Hashable, Codable {
    case detail(UUID)
}

extension TableRoute: RawRepresentable {
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

extension TableRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            TableRouteDestinationView(itemId: itemId)
                .navigationAutoReceive(TableDetailRoute.self)
        }
    }
}

extension TableRoute: ItemDetailRoute {
    public static func detailRoute(itemId: UUID) -> Self {
        TableRoute.detail(itemId)
    }

    public func reset(detail: UUID) -> Self {
        TableRoute.detail(detail)
    }

    public func detail() -> UUID? {
        switch self {
        case .detail(let id): return id
        }
    }
}

struct TableRouteDestinationView: View {
    let itemId: UUID

    @Environment(TableRootModel.self) private var root

    var body: some View {
        if let model = root.itemController.itemSync(for: itemId) {
            DetailRootView(root: root, model: model)
        }
    }
}
