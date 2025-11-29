// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftUI

public enum GeneratorRoute: Equatable, Hashable, Codable {
    case detail(UUID)
}

extension GeneratorRoute: RawRepresentable {
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

extension GeneratorRoute: ItemDetailRoute {
    public func reset(detail: UUID) -> Self {
        GeneratorRoute.detail(detail)
    }
    
    public func detail() -> UUID? {
        switch self {
            case .detail(let id): return id
        }
    }
}

extension GeneratorRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            GeneratorRouteDestinationView(itemId: itemId)
                .navigationDestination(GeneratorDetailRoute.self)
                .navigationAutoReceive(GeneratorDetailRoute.self)
        }
    }
}

struct GeneratorRouteDestinationView: View {
    let itemId: UUID

    @Environment(GeneratorRootModel.self) private var root
    
    var body: some View {
        DetailRootView(root: root, model: root.itemController.itemOrEmpty(for: itemId))
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
            .environment(root.rootController)
    }
}
