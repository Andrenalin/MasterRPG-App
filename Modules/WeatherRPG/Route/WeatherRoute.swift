// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    WeatherRouteDestinationView(itemId: WeatherModel.previewId)
}

public enum WeatherRoute: Equatable, Hashable, Codable {
    case detail(UUID)
}

extension WeatherRoute: RawRepresentable {
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

extension WeatherRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            WeatherRouteDestinationView(itemId: itemId)
                .navigationAutoReceive(WeatherDetailRoute.self)
        }
    }
}

extension WeatherRoute: ItemDetailRoute {
    public static func detailRoute(itemId: UUID) -> Self {
        WeatherRoute.detail(itemId)
    }

    public func reset(detail: UUID) -> Self {
        WeatherRoute.detail(detail)
    }

    public func detail() -> UUID? {
        switch self {
        case .detail(let id): return id
        }
    }
}

struct WeatherRouteDestinationView: View {
    let itemId: UUID

    @Environment(WeatherRootModel.self) private var root

    var body: some View {
        if let model = root.itemController.itemSync(for: itemId) {
            DetailRootView(root: root, model: model)
        }
    }
}
