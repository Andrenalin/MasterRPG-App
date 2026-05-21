// @copyright André Trettin

import CoreRPG
import SwiftUI

public enum PhotoRoute: Equatable, Hashable, Codable {
    case detail(UUID)
}

extension PhotoRoute: RawRepresentable {
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

extension PhotoRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            PhotoRouteDestinationView(itemId: itemId)
                .navigationAutoReceive(PhotoDetailRoute.self)
        }
    }
}

extension PhotoRoute: ItemDetailRoute {
    public static func detailRoute(itemId: UUID) -> Self {
        PhotoRoute.detail(itemId)
    }

    public func reset(detail: UUID) -> Self {
        PhotoRoute.detail(detail)
    }

    public func detail() -> UUID? {
        switch self {
            case .detail(let id): return id
        }
    }
}

struct PhotoRouteDestinationView: View {
    let itemId: UUID

    @Environment(PhotoRootModel.self) private var root

    var body: some View {
        if let model = root.itemController.itemSync(for: itemId) {
            DetailRootView(root: root, model: model)
        }
    }
}
