// @copyright André Trettin

import CoreRPG

import SwiftUI

public enum CharacterRoute: Equatable, Hashable, Codable {
    case detail(UUID)
}

extension CharacterRoute: RawRepresentable {
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

extension CharacterRoute: NavigationDestination {
    public var body: some View {
        switch self {
        case .detail(let itemId):
            CHaracterRouteDestinationView(itemId: itemId)
                .navigationAutoReceive(CharacterDetailRoute.self)
        }
    }
}

extension CharacterRoute: ItemDetailRoute {
    public func reset(detail: UUID) -> Self {
        CharacterRoute.detail(detail)
    }
    
    public func detail() -> UUID? {
        switch self {
            case .detail(let id): return id
        }
    }
}

struct CHaracterRouteDestinationView: View {
    let itemId: UUID

    @Environment(CharacterRootModel.self) private var root

    var body: some View {
        if let model = root.itemController.itemSync(for: itemId) {
            DetailRootViewWrapper(root: root, model: model)
        }
    }
}

private struct DetailRootViewWrapper: View {
    let root: CharacterRootModel
    let model: ValueModel

    var body: some View {
        DetailRootView(root: root, model: model)
            .equatable()
    }
}
