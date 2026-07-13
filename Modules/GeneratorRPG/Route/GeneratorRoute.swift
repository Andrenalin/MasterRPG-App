// @copyright André Trettin


import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    GeneratorRouteDestinationView(itemId: GeneratorModel.previewId)
}

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
    public static func detailRoute(itemId: UUID) -> Self {
        GeneratorRoute.detail(itemId)
    }

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
                .navigationAutoReceive(GeneratorDetailRoute.self)
        }
    }
}

struct GeneratorRouteDestinationView: View {
    let itemId: UUID

    @Environment(GeneratorRootModel.self) private var root
    
    var body: some View {
        if let model = root.itemController.itemSync(for: itemId) {
            DetailRootView(root: root, model: model)
        }
    }
}
